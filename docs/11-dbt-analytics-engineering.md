# Analytics Engineering: dbt Integration (The "0.1%" Upgrade)

This document details the transition from infrastructure-managed SQL views (Terraform) to true **Analytics Engineering** using **dbt (Data Build Tool)**. This shift represents a maturity leap from "Data Ops" to "Data Platform Engineering".

## 1. Goal & Philosophy

### Why dbt?
Managing complex SQL logic inside Terraform strings (`bigquery.tf`) is brittle and hard to test. By adopting dbt, we achieve:
1.  **Separation of Concerns**:
    *   **Terraform**: Manages *Infrastructure* (Datasets, Service Accounts, Buckets, IAM).
    *   **dbt**: Manages *Business Logic* (SQL Transformations, Views, Tables, Documentation).
2.  **Data Quality Testing**: We can assert `unique`, `not_null`, and `accepted_values` tests on our data models.
3.  **Portability**: The project can be deployed to any Google Cloud Project ID without code changes.

### The "1%" Standard
Most student or junior projects stop at "ingesting data". By implementing dbt, we demonstrate:
*   Use of **Jinja templating** for dynamic SQL.
*   **Dependency Management** (Lineage graphs).
*   **Environment Awareness** (Dev vs. Prod profiles).

---

## 2. dbt Architecture

We organize the dbt project into layers, following industry best practices (though simplified for this project).

| Layer | dbt Folder | Materialization | Purpose |
| :--- | :--- | :--- | :--- |
| **Sources** | `models/sources.yml` | *Source* | References the raw/curated tables created by Dataflow (`pmp_curated.velib_station_status`). |
| **Marts** | `models/marts/` | `view` | Business logic, aggregations, and joins. This is where analysts query. |

### Dynamic Connection Profile
The `dbt/profiles.yml` is configured to be **fully dynamic** using environment variables. This ensures CI/CD compatibility.

```yaml
# dbt/profiles.yml
paris_mobility_pulse:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: "{{ env_var('PROJECT_ID') }}"  # <--- Reads from .env
      dataset: pmp_dbt_dev
```

---

## 3. Implementation Details

### A. Source Definition (`sources.yml`)
Instead of hardcoding `${var.project_id}.pmp_curated` in SQL, we define sources logically.

```yaml
# dbt/models/sources.yml
sources:
  - name: pmp_curated
    database: "{{ env_var('PROJECT_ID') }}"
    tables:
      - name: velib_station_status
      - name: velib_station_information
```

### B. Migrated Models
We successfully migrated the SQL logic from `infra/terraform/bigquery.tf` into specific dbt models.

#### 1. `velib_totals_hourly_aggregate` (Base Logic)
*   **Source**: `{{ source('pmp_curated', 'velib_station_status') }}`
*   **Logic**: Aggregates raw status updates into hourly buckets (avg bikes, empty stations).
*   **File**: `dbt/models/marts/velib_totals_hourly_aggregate.sql`

#### 2. `velib_totals_hourly_paris` (Filtered Logic)
*   **Ref**: `{{ ref('velib_totals_hourly_aggregate') }}` (Depend on the model above).
*   **Source**: `{{ source('pmp_curated', 'velib_station_information') }}` (Join with metadata).
*   **Filter**: `WHERE avg_coverage_ratio >= 0.999`.
*   **File**: `dbt/models/marts/velib_totals_hourly_paris.sql`

---

## 4. Workflow (How to Run)

### Prerequisites
You must have the `PROJECT_ID` environment variable set (sourced from `.env`).

```bash
source .env
```

### Deployment Commands

1.  **Install Dependencies** (if using packages):
    ```bash
    dbt deps
    ```

2.  **Run Models** (Create Views/Tables in BigQuery):
    ```bash
    dbt run
    ```

3.  **Test Models** (Verify Data Quality):
    ```bash
    dbt test
    ```

4.  **Generate Documentation** (Optional):
    ```bash
    dbt docs generate
    dbt docs serve
    ```

---

## 5. Migration Status (Completed)
We have successfully:
1.  **Removed** the legacy `view` blocks from `infra/terraform/bigquery.tf`.
2.  **Updated** the `Makefile` to automatically install dbt and run models during `deploy`.
3.  **Deploying**: Running `make deploy` now handles both Infrastructure (Terraform) and Analytics (dbt) in a single command.

## 6. Future Improvements
*   Add more Data Quality tests (e.g., `accepted_values` for status fields).
*   Implement dbt Docs for auto-generated data dictionaries.
*   Set up a CI/CD pipeline step to run `dbt test` on Pull Requests.
