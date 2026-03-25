# IDFM Transit Disruptions — Implementation Checkpoint

> [!NOTE]
> This document tracks **what has been implemented** from the [IDFM vision doc](./12-idfm-transit-disruptions.md). It serves as a progress checkpoint.

---

## Phase 1: Reference Data + Raw Ingestion ✅

All Phase 1 items from doc 12 are **complete and deployed**.

### 1.1 IDFM Collector Service

**Service**: `pmp-idfm-collector` (Cloud Run)

| File | Purpose |
|---|---|
| `collectors/idfm/main.py` | Flask app — polls IDFM bulk disruptions API, writes directly to BigQuery |
| `collectors/idfm/requirements.txt` | Dependencies: Flask, requests, google-cloud-bigquery |

**How it works**:
1. Cloud Scheduler sends a POST to the Cloud Run service every 10 minutes
2. The collector calls `GET /disruptions_bulk/disruptions/v2` with the API key
3. Each disruption is wrapped in the standard envelope schema and inserted into `pmp_raw.idfm_disruptions_raw`

**Envelope schema** (same pattern as Vélib):

| Column | Type | Example Value |
|---|---|---|
| `ingest_ts` | TIMESTAMP | `2026-02-22 16:00:02 UTC` |
| `event_ts` | TIMESTAMP | `2026-02-22 16:00:02 UTC` |
| `source` | STRING | `idfm_disruptions` |
| `event_type` | STRING | `disruption` |
| `key` | STRING | `95092f7e-0bf1-11f1-b327-0a58a9feac02` |
| `payload` | JSON | Full disruption object |

### 1.2 Terraform Resources

| Resource | File | Type |
|---|---|---|
| `idfm_disruptions_raw` table | `bigquery_idfm.tf` | BigQuery table in `pmp_raw`, partitioned by day on `ingest_ts`, clustered by `source`, `event_type` |
| `pmp-idfm-collector` | `cloud_run_idfm_collector.tf` | Cloud Run v2 service |
| `idfm-poll-every-10min` | `cloud_scheduler_idfm.tf` | Cloud Scheduler job (`*/10 * * * *`, Europe/Paris) |
| `pmp-idfm-api-key` secret | `secrets.tf` | Secret Manager secret + version |
| `pmp-idfm-collector-sa` | `iam.tf` | Service account with BigQuery DataEditor on `pmp_raw` + Secret Accessor on API key |
| Scheduler → Cloud Run invoke | `iam.tf` | IAM binding for scheduler to invoke the collector |

### 1.3 Reference Data (dbt Seeds)

| File | Dataset | Table | Purpose |
|---|---|---|---|
| `dbt/seeds/idfm_stops_reference.csv` | `pmp_dbt_dev_curated` | `idfm_stops_reference` | Stop coordinates (`zda_id`, `name`, `lat`, `lon`, `town`, `type`) |
| `dbt/seeds/idfm_zones_darret.csv` | `pmp_dbt_dev_curated` | `idfm_zones_darret` | Bridge table mapping `ZdCId` → `ZdAId` (sourced from IDFM Référentiel des arrêts) |

The disruptions API references stops by **Zone de Correspondance (ZdC)** IDs, while the stops reference file is keyed by **Zone d'Arrêt (ZdA)** IDs. The `idfm_zones_darret` seed bridges the two.

---

## Phase 2: Curated Layer (dbt) — In Progress

### 2.1 Staging Model ✅

**File**: `dbt/models/curated/stg_idfm_disruptions.sql`

Extracts fields from the raw JSON `payload` column into a structured **incremental** table in `pmp_dbt_dev_curated`.

```sql
SELECT
  ingest_ts,
  JSON_VALUE(payload, '$.id')           AS disruption_id,
  JSON_VALUE(payload, '$.cause')        AS cause,
  JSON_VALUE(payload, '$.severity')     AS severity,
  JSON_VALUE(payload, '$.title')        AS title,
  JSON_VALUE(payload, '$.shortMessage') AS short_message,
  JSON_VALUE(payload, '$.message')      AS message_html,
  PARSE_TIMESTAMP('%Y%m%dT%H%M%S', JSON_VALUE(payload, '$.lastUpdate')) AS last_update,
  JSON_QUERY(payload, '$.applicationPeriods') AS application_periods,
  JSON_QUERY(payload, '$.impactedSections')   AS impacted_sections
FROM pmp_raw.idfm_disruptions_raw
WHERE ingest_ts > TIMESTAMP_SUB((SELECT MAX(ingest_ts) FROM this), INTERVAL 1 MINUTE)
```

**Table config**:
- **Materialized**: `incremental` (merge on `disruption_id` + `ingest_ts`)
- **Partitioned by**: `MONTH` on `ingest_ts`
- **Clustered by**: `severity`
- **Safety overlap**: 1 minute lookback to avoid missing rows
- **Dataset**: `pmp_dbt_dev_curated`

**dbt config changes**:
- `dbt_project.yml` — Added `curated:` folder config (`+schema: curated`, `+materialized: table`)
- `models/sources.yml` — Added `pmp_raw` source with `idfm_disruptions_raw` table

### 2.2 Scheduled dbt Runner ✅

Automated hourly dbt runs via Cloud Run Job + Cloud Scheduler.

| Resource | File | Purpose |
|---|---|---|
| `dbt/Dockerfile` | `dbt/Dockerfile` | Lightweight `python:3.11-slim` + `dbt-bigquery` image |
| `dbt/.dockerignore` | `dbt/.dockerignore` | Excludes `target/`, `dbt_packages/`, `logs/` |
| `pmp-dbt-runner` | `cloud_run_dbt_runner.tf` | Cloud Run Job (10 min timeout) |
| `dbt-run-every-hour` | `cloud_run_dbt_runner.tf` | Cloud Scheduler (`0 * * * *`, Europe/Paris) |
| `pmp-dbt-runner-sa` | `iam.tf` | Service account: BigQuery dataViewer on `pmp_raw`, dataEditor + jobUser project-level |
| Scheduler → Job invoke | `iam.tf` | IAM binding for scheduler to invoke the Cloud Run Job |

**Operations**:
- `pmpctl.sh up` resumes the `dbt-run-every-hour` scheduler (added to `SCHED_JOBS` array)
- `pmpctl.sh down` pauses it
- `build.sh` builds and deploys the dbt-runner container image

### 2.3 Flattened Disruptions Model ✅

**File**: `dbt/models/curated/idfm_disruptions.sql`

Extracts the latest snapshot of each disruption, unnests the `impactedSections` array, and resolves stop coordinates via a **two-step join**:

```
stop_area:IDFM:XXXXX (ZdC ID)
  → idfm_zones_darret (ZdCId → ZdAId)
    → idfm_stops_reference (zda_id → lat, lon, name)
```

**Table config**:
- **Materialized**: `view`
- **Dataset**: `pmp_dbt_dev_curated`
- **Output**: Resolves `stop_area:IDFM:XXXX` ZdC IDs through the zones d'arrêt bridge table to pull `lat`, `lon`, and `name` for from/to stops. Only returns `BLOQUANTE` disruptions (complete service stops) — `PERTURBEE` (degraded service) is excluded as it rarely drives measurable Vélib demand spikes.

### 2.4 Cross-Source Geomart ✅

**File**: `dbt/models/marts/geomart_disruption_impact.sql`

Spatially joins **active IDFM BLOQUANTE disruptions** with **Vélib stations within 750 metres** using BigQuery geography functions. Bus disruptions are excluded (`NOT REGEXP_CONTAINS(title, r'^Bus ')`) as they rarely generate enough stranded commuters to measurably impact Vélib.

**How it works**:
1. Converts the `from_lat/from_lon` and `to_lat/to_lon` columns from `idfm_disruptions` into BigQuery `GEOGRAPHY` points via `ST_GEOGPOINT`
2. Selects the **latest** row per Vélib station from `velib_station_information` using `ROW_NUMBER()` (avoids scanning full history)
3. Performs a `CROSS JOIN` filtered by `ST_DWITHIN(stop_geo, station_geo, 750)` to find all stations within 750 m of either the `from` or `to` disrupted stop
4. Outputs the exact distances in metres (`distance_to_from_stop_meters`, `distance_to_to_stop_meters`)

**Table config**:
- **Materialized**: `view`
- **Dataset**: `pmp_dbt_dev_pmp_marts`
- **Key metric**: `MIN(distance_to_from_stop_meters, distance_to_to_stop_meters)` → nearest affected stop distance per Vélib station

---

## Phase 3: Dashboard ⬜

Not started.

## Phase 4: Operations ⬜

Not started.

---

## Known Issues

### BigQuery Region Mismatch (Resolved)

`pmp_raw` was originally in `europe-west9`, while `pmp_curated` and all dbt-managed datasets are in `EU`. This caused `Dataset not found in location EU` errors during `dbt run`. **Fixed** by recreating `pmp_raw` in EU.

### Null lat/lon in `idfm_disruptions` View (Resolved)

The disruptions API `impactedSections` references stops as `stop_area:IDFM:XXXXX`, where `XXXXX` is a **Zone de Correspondance (ZdC)** ID — not a Zone d'Arrêt (ZdA) ID. The original view joined directly on `idfm_stops_reference.zda_id`, which never matched because the ID hierarchy is:

```
ArR (stop point) → ZdA (stop area) → ZdC (interchange zone)
```

**Fixed** by adding an `idfm_zones_darret` seed (sourced from IDFM Référentiel des arrêts) as a bridge table that maps `ZdCId → ZdAId`. The view now performs a two-step join through this bridge table to resolve coordinates.

---

## Verification

### Confirm raw data is flowing

```sql
SELECT COUNT(*) AS row_count,
       MIN(ingest_ts) AS first_ingest,
       MAX(ingest_ts) AS last_ingest
FROM `paris-mobility-pulse.pmp_raw.idfm_disruptions_raw`
```

### Confirm staging model output (after `dbt run`)

```sql
SELECT disruption_id, cause, severity, title, last_update
FROM `paris-mobility-pulse.pmp_dbt_dev_curated.stg_idfm_disruptions`
LIMIT 10
```

### Confirm incremental is working (after 2nd+ run)

```sql
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT ingest_ts) AS distinct_polls
FROM `paris-mobility-pulse.pmp_dbt_dev_curated.stg_idfm_disruptions`
```

### Confirm lat/lon resolution in flattened view

```sql
SELECT disruption_id, title, from_zdc_id, from_stop_name, from_lat, from_lon
FROM `paris-mobility-pulse.pmp_dbt_dev_curated.idfm_disruptions`
LIMIT 10
```

All rows should have non-null `from_lat`/`from_lon` values.

### Confirm geomart spatial join is working

```sql
SELECT
  title,
  from_stop_name,
  velib_station_name,
  velib_station_capacity,
  ROUND(LEAST(distance_to_from_stop_meters, distance_to_to_stop_meters)) AS nearest_stop_distance_m
FROM `paris-mobility-pulse.pmp_dbt_dev_pmp_marts.geomart_disruption_impact`
ORDER BY nearest_stop_distance_m ASC
LIMIT 10
```

Should return Vélib stations within 750 m of active BLOQUANTE disruption stops (excluding bus lines), with real distances in metres.
