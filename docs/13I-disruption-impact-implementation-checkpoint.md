# Cross-Source Disruption Impact — Implementation Checkpoint

> [!NOTE]
> This document tracks **what has been implemented** from the [cross-source analysis vision doc](./13-cross-source-disruption-impact-analysis.md). It serves as a progress checkpoint.

---

## Phase 1: Foundation Views ✅

Three new dbt mart views that provide the clean, latest-state Vélib data needed for spatial analysis.

### 1.1 `velib_station_information_latest`

**File**: `dbt/models/marts/velib_station_information_latest.sql`
**Materialization**: view

Latest metadata row per Vélib station from the slowly-changing `velib_station_information` source. Deduplicated via `ROW_NUMBER() OVER (PARTITION BY station_id ORDER BY event_ts DESC, ingest_ts DESC)`.

### 1.2 `velib_latest_state`

**File**: `dbt/models/marts/velib_latest_state.sql`
**Materialization**: view

Most recent status snapshot per station from `velib_station_status`. Single row per station, ordered by `event_ts DESC`.

### 1.3 `velib_latest_state_enriched`

**File**: `dbt/models/marts/velib_latest_state_enriched.sql`
**Materialization**: view

Joins `velib_latest_state` with `velib_station_information_latest` on `station_id`. Produces one fully-enriched row per station with live status + metadata (name, lat, lon, capacity, address).

---

## Phase 2: Spatial Impact View ✅

### 2.1 `geomart_disruption_impact`

**File**: `dbt/models/marts/geomart_disruption_impact.sql`
**Materialization**: view

Spatial cross join between active BLOQUANTE disruptions and all Vélib stations. Uses `ST_DWITHIN` to retain only stations within **500 metres** of a disrupted transit stop. One row per **(disruption × Vélib station)** pair.

**Key columns**:

| Column | Description |
|---|---|
| `disruption_id` | IDFM disruption identifier |
| `from_stop_name` / `from_lat` / `from_lon` | Disrupted segment origin stop with coordinates |
| `to_stop_name` / `to_lat` / `to_lon` | Disrupted segment destination stop with coordinates |
| `velib_station_id` | Nearby Vélib station |
| `distance_to_from_stop_meters` | Exact distance to the from-stop |
| `distance_to_to_stop_meters` | Exact distance to the to-stop |

---

## Phase 3: A/B Comparison Mart ✅

### 3.1 `mart_disruption_impact_comparison`

**File**: `dbt/models/marts/mart_disruption_impact_comparison.sql`
**Materialization**: view

The primary analytical output. For each active BLOQUANTE disruption, compares the **average Vélib fill rate** inside the 500m impact zone against a **control group** of stations unaffected by any active disruption.

**Logic (5 CTEs)**:

```
geomart          → pulls from geomart_disruption_impact, computes nearest_stop_distance_m
stations         → pulls from velib_latest_state_enriched, computes fill_rate = bikes / capacity
impacted_pool    → DISTINCT station_ids appearing in ANY active disruption
control_stats    → AVG fill_rate for stations NOT IN impacted_pool (single row)
disruption_zone  → per-disruption AVG fill_rate for stations IN that disruption's zone
Final SELECT     → CROSS JOIN (one control row × all disruptions) to compare side by side
```

**Output schema** (one row per active disruption):

| Column | Description |
|---|---|
| `disruption_id` | IDFM disruption identifier |
| `disruption_title` | Human-readable label (e.g. "Métro 14 : Trafic interrompu") |
| `cause` | `PERTURBATION` or `TRAVAUX` |
| `severity` | Always `BLOQUANTE` (filtered upstream) |
| `last_update` | When the disruption became active |
| `from_stop_name` / `from_lat` / `from_lon` | Origin stop + coordinates (map-ready) |
| `to_stop_name` / `to_lat` / `to_lon` | Destination stop + coordinates (map-ready) |
| `stations_in_impact_zone` | Count of Vélib stations within 500m |
| `closest_station_distance_m` | Distance to the nearest affected Vélib station |
| `zone_fill_rate_pct` | Avg fill rate (%) inside the impact zone |
| `zone_avg_bikes_available` | Avg bikes available inside the zone |
| `control_fill_rate_pct` | Avg fill rate (%) for all unaffected stations |
| `control_avg_bikes_available` | Avg bikes available in the control group |
| `control_station_count` | Number of stations in the control group |
| `fill_rate_delta_pct` | `zone - control` in percentage points — **negative = demand spike** |

**Ordered by** `fill_rate_delta_pct ASC` — most-impacted disruptions appear first.

---

## Design Decisions

### Control Group Definition
Rather than a fixed radius exclusion (1–2km as in the theory doc), the control group is defined as **all stations not within 500m of any active disruption**. This avoids the need to tune a second radius parameter and naturally produces the largest possible unaffected sample.

### Why `materialized='view'` (not BigQuery materialized view)
BigQuery native materialized views prohibit `CROSS JOIN`, `NOT IN (subquery)`, and top-level `ORDER BY` — all of which this model uses. It remains a regular view. To pre-compute results for dashboard performance, change to `materialized='table'` and schedule a `dbt run` every 15–30 minutes via Cloud Scheduler.

### Map Readiness
The output includes `from_lat`, `from_lon`, `to_lat`, `to_lon` for every disruption. These can be used directly in Looker Studio geo charts or Kepler.gl to render the disrupted transit segment as a line and colour Vélib stations by their `fill_rate_delta_pct`.

---

## Data Sources

| Source | URL |
|---|---|
| IDFM Disruptions API | `https://prim.iledefrance-mobilites.fr/marketplace/disruptions_bulk/disruptions/v2` |
| IDFM Stop Reference (ZdC/ZdA bridge) | [data.iledefrance-mobilites.fr — Référentiel des arrêts : Zones d'arrêts](https://data.iledefrance-mobilites.fr/explore/dataset/referentiel-des-arrets-idfm/information/) |
| Vélib Open Data (GBFS) | [velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole](https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole) |

---

## Verification Query

```sql
-- Check the view is returning rows and the delta is non-trivial
SELECT
    disruption_title,
    stations_in_impact_zone,
    zone_fill_rate_pct,
    control_fill_rate_pct,
    fill_rate_delta_pct
FROM `paris-mobility-pulse.pmp_dbt_dev_pmp_marts.mart_disruption_impact_comparison`
ORDER BY fill_rate_delta_pct ASC
LIMIT 10;
```

Expected: at least one row per active BLOQUANTE disruption, with `fill_rate_delta_pct` in the range −40 to +10.
