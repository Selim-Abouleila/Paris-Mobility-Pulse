# BigQuery Marts Layer

This document explains the **Marts Layer** for Paris Mobility Pulse: why it exists, what it contains, and how to manage it with Terraform.

## 1. Why a Marts Layer?

### The Problem: Append-Only Fact Tables Are Not Dashboard-Friendly

The curated table `pmp_curated.velib_station_status` is an **append-only fact table**:
*   Every Pub/Sub snapshot creates **one row per station** as of that snapshot's timestamp.
*   A single station (e.g., `station_id = "16107"`) will have **thousands of rows** over time (one for every ingestion cycle).
*   Dashboards need the **latest state** for each station, not the full history.

Querying the append-only table directly for "current status" is inefficient:
```sql
-- BAD: Scans the entire partitioned table, expensive
SELECT * FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
WHERE ingest_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
```

### The Solution: Marts Layer

The **marts layer** provides **dashboard-ready views** that abstract away the complexity:
*   `pmp_marts.velib_latest_state` → **One row per station** (the most recent status).
*   Downstream consumers (Looker Studio, API endpoints, aggregations) query the marts layer instead of the raw fact table.
*   The view is **always up-to-date** (no caching, no batch jobs).

---

## 2. What Was Created (Step 4A)

### Dataset
*   **Name**: `paris-mobility-pulse.pmp_marts`
*   **Location**: `EU`
*   **Purpose**: Holds all marts-layer views and aggregated tables for analytics.

### View: `velib_latest_state`
*   **Full Name**: `paris-mobility-pulse.pmp_marts.velib_latest_state`
*   **Source**: `paris-mobility-pulse.pmp_curated.velib_station_status`
*   **Logic**: Window function to get the latest row per `station_id`.

#### SQL Definition
```sql
SELECT * EXCEPT(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY station_id
      ORDER BY event_ts DESC, ingest_ts DESC
    ) AS rn
  FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
)
WHERE rn = 1
```

This query:
1.  **Partitions** all rows by `station_id`.
2.  **Orders** within each partition by `event_ts DESC, ingest_ts DESC` (most recent first).
3.  **Assigns** `ROW_NUMBER()` → the first row gets `rn = 1`.
4.  **Filters** to keep only `rn = 1` → **one row per station**.

---

## 3. Manual Creation (For Understanding/Debugging)

These commands show how to create the dataset and view manually using `bq`. However, **Terraform is the source of truth** going forward.

### Create Dataset
```bash
bq mk --location=EU --dataset paris-mobility-pulse:pmp_marts
```

### Create View
```bash
bq mk --use_legacy_sql=false --view '
SELECT * EXCEPT(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY station_id
      ORDER BY event_ts DESC, ingest_ts DESC
    ) AS rn
  FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
)
WHERE rn = 1
' paris-mobility-pulse:pmp_marts.velib_latest_state
```

> **Important**: Do not create or modify these resources manually. Use Terraform to ensure consistency and version control.

---

## 4. Terraform Management (Source of Truth)

### Resources

The marts layer is managed by the following Terraform resources:

**Dataset**: `google_bigquery_dataset.pmp_marts`
*   File: [`infra/terraform/bigquery.tf`](file:///c:/Git%20Projects/Paris-Mobility-Pulse/infra/terraform/bigquery.tf)
*   Attributes:
    ```hcl
    dataset_id = "pmp_marts"
    location   = "EU"
    ```

**View**: `google_bigquery_table.velib_latest_state`
*   File: [`infra/terraform/bigquery.tf`](file:///c:/Git%20Projects/Paris-Mobility-Pulse/infra/terraform/bigquery.tf)
*   Attributes:
    ```hcl
    dataset_id = google_bigquery_dataset.pmp_marts.dataset_id
    table_id   = "velib_latest_state"

    view {
      query = <<-SQL
        SELECT * EXCEPT(rn)
        FROM (
          SELECT
            *,
            ROW_NUMBER() OVER (
              PARTITION BY station_id
              ORDER BY event_ts DESC, ingest_ts DESC
            ) AS rn
          FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
        )
        WHERE rn = 1
      SQL
      use_legacy_sql = false
    }

    depends_on = [google_bigquery_table.velib_station_status]
    ```

### Apply Changes

To apply Terraform changes:

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

---

## 5. Import Commands (First-Time Setup)

Since the dataset and view were created manually before Terraform, they must be **imported** into Terraform state.

### Prerequisites
Run `terraform init` before importing.

### Import Order

**1. Import the Marts Dataset**
```bash
terraform import google_bigquery_dataset.pmp_marts projects/paris-mobility-pulse/datasets/pmp_marts
```

**2. Import the Latest State View**
```bash
terraform import google_bigquery_table.velib_latest_state projects/paris-mobility-pulse/datasets/pmp_marts/tables/velib_latest_state
```

### Verify
After importing, verify that Terraform recognizes the resources:
```bash
terraform plan
# Expected: "No changes. Your infrastructure matches the configuration."
```

---

## 6. Verification

### Row Count Comparison
Check curated table vs. marts view:

```bash
# Curated table: thousands of rows (append-only history)
bq query --use_legacy_sql=false --nouse_cache '
SELECT COUNT(*) as total_rows
FROM `paris-mobility-pulse.pmp_curated.velib_station_status`'

# Marts view: ~1400 rows (one per station)
bq query --use_legacy_sql=false --nouse_cache '
SELECT COUNT(*) as total_stations
FROM `paris-mobility-pulse.pmp_marts.velib_latest_state`'
```

### Sample Latest State
Query the marts view to see the latest status for each station:

```bash
bq query --use_legacy_sql=false --nouse_cache '
SELECT 
  station_id, 
  station_code, 
  num_bikes_available, 
  num_docks_available, 
  mechanical_available,
  ebike_available,
  event_ts, 
  ingest_ts
FROM `paris-mobility-pulse.pmp_marts.velib_latest_state`
ORDER BY station_id
LIMIT 10'
```

### Expected Results
*   Each `station_id` appears **exactly once**.
*   `event_ts` and `ingest_ts` represent the **most recent** snapshot.

---

## 7. Phase 1 vs Future

### Phase 1 (Current)
*   ✅ **Dataset**: `pmp_marts`
*   ✅ **View**: `velib_latest_state` (latest status per station)
*   ✅ **Source**: Curated table `pmp_curated.velib_station_status`

### Future Enhancements

**Station Dimensions (Step 4B)**
*   Ingest `station_information` API (static metadata: lat/lon, name, capacity).
*   Store in `pmp_curated.velib_station_information` (slowly changing dimension).

**Enriched Marts (Step 4C)**
*   Create view: `velib_latest_state_enriched`
*   Join `velib_latest_state` with `velib_station_information` to add geolocation context.
*   Example:
    ```sql
    SELECT 
      s.station_id,
      s.num_bikes_available,
      s.event_ts,
      i.name,
      i.lat,
      i.lon,
      i.capacity
    FROM `pmp_marts.velib_latest_state` s
    LEFT JOIN `pmp_curated.velib_station_information` i
      ON s.station_id = i.station_id
    ```

**Aggregated Marts (Step 4D)**
*   Create bucketed aggregation views (e.g., availability by arrondissement, hourly rollups).
*   Example: `velib_availability_by_hour`, `velib_availability_by_region`.

**Multiple APIs (Step 5)**
*   Expand to other Paris mobility APIs (e.g., Autolib, Cityscoot).
*   Create analogous marts: `autolib_latest_state`, `cityscoot_latest_state`.

---

## 8. Related Documentation

*   **Terraform README**: [`infra/terraform/README.md`](file:///c:/Git%20Projects/Paris-Mobility-Pulse/infra/terraform/README.md) - import commands, outputs, validation.
*   **Dataflow Curation**: [`docs/04-dataflow-curation.md`](file:///c:/Git%20Projects/Paris-Mobility-Pulse/docs/04-dataflow-curation.md) - how curated data is produced.
*   **Terraform IAC**: [`docs/03-terraform-iac.md`](file:///c:/Git%20Projects/Paris-Mobility-Pulse/docs/03-terraform-iac.md) - Terraform setup and best practices.
