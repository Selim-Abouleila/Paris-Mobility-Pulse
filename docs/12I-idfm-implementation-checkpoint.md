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

### 1.3 Reference Data (dbt Seed)

| File | Dataset | Table |
|---|---|---|
| `dbt/seeds/idfm_stops_reference.csv` | `pmp_dbt_dev_curated` | `idfm_stops_reference` |

Contains transit stop coordinates (`ZdAId`, `name`, `lat`, `lon`, `town`, `type`) for geographic cross-joins with Vélib.

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

### 2.3 Flattened Disruptions Model ⬜

`idfm_disruptions.sql` — Flatten `impactedSections` array → one row per impacted section per disruption.

### 2.4 Cross-Source Mart ⬜

`disruptions_near_velib.sql` — Geographic join between disrupted stops and nearby Vélib stations.

---

## Phase 3: Dashboard ⬜

Not started.

## Phase 4: Operations ⬜

Not started.

---

## Known Issues

### BigQuery Region Mismatch (Resolved)

`pmp_raw` was originally in `europe-west9`, while `pmp_curated` and all dbt-managed datasets are in `EU`. This caused `Dataset not found in location EU` errors during `dbt run`. **Fixed** by recreating `pmp_raw` in EU.

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
