# Paris Mobility Pulse — Terraform Infrastructure

This directory contains the Terraform configuration for the **Paris Mobility Pulse** project's GCP infrastructure.

## Managed Resources

### APIs (`apis.tf`)
Dataflow, Pub/Sub, BigQuery, Storage, IAM, Cloud Resource Manager, Cloud Run, Cloud Scheduler, Secret Manager.

### Pub/Sub (`pubsub.tf`)

| Resource | Name | Purpose |
| :--- | :--- | :--- |
| **Topic** | `pmp-events` | Main event bus (station status snapshots) |
| **Subscription** | `pmp-events-dataflow-sub` | Pull → Dataflow streaming pipeline |
| **Subscription** | `pmp-events-sub` | Debug/manual pull (31-day TTL) |
| **Subscription** | `pmp-events-to-bq-sub` | Push → `pmp-bq-writer` Cloud Run (raw ingestion) |
| **Topic** | `pmp-velib-station-info` | Station information (metadata) events |
| **Subscription** | `pmp-velib-station-info-to-bq-sub` | Push → `pmp-velib-station-info-writer` Cloud Run |
| **Topic** | `pmp-velib-station-info-push-dlq` | Dead Letter Queue for station info push failures |
| **Subscription** | `pmp-velib-station-info-push-dlq-hold-sub` | DLQ hold (7-day retention for replay) |
| **Subscription** | `pmp-velib-station-info-push-dlq-to-bq-sub` | DLQ → BigQuery export for analysis |

### BigQuery (`bigquery.tf`)

| Dataset | Table / View | Type | Details |
| :--- | :--- | :--- | :--- |
| `pmp_raw` | `velib_station_status_raw` | Table | Raw JSON payloads, partitioned by `ingest_ts` |
| `pmp_curated` | `velib_station_status` | Table | Flattened station rows, partitioned by day, clustered by `station_id` |
| `pmp_curated` | `velib_station_information` | Table | Station metadata (name, lat/lon, capacity), partitioned by day |
| `pmp_marts` | `velib_latest_state` | View | Latest status per station (ROW_NUMBER window) |
| `pmp_marts` | `velib_station_information_latest` | View | Latest metadata per station |
| `pmp_marts` | `velib_latest_state_enriched` | View | Joins latest status + latest metadata (name, lat/lon) |
| `pmp_ops` | `velib_dlq_raw` | Table | Pub/Sub DLQ raw messages, partitioned by `publish_time` |
| `pmp_ops` | `velib_station_status_curated_dlq` | Table | Dataflow DLQ errors, partitioned by `dlq_ts` |

> **dbt-managed views**: `velib_totals_hourly_aggregate`, `velib_totals_hourly`, and `velib_totals_hourly_paris` are managed by dbt in `dbt/models/` and have been removed from Terraform. See [docs/11-dbt-analytics-engineering.md](../../docs/11-dbt-analytics-engineering.md).

### Cloud Run (`cloud_run_*.tf`)

| Service | File | Purpose |
| :--- | :--- | :--- |
| `pmp-velib-collector` | `cloud_run_velib_collector.tf` | Collects Vélib station_status snapshots → publishes to `pmp-events` |
| `pmp-velib-station-info-collector` | `cloud_run_station_info.tf` | Collects station_information metadata → publishes to `pmp-velib-station-info` |
| `pmp-velib-station-info-writer` | `cloud_run_station_info.tf` | Receives push from Pub/Sub → writes to BigQuery |
| `pmp-bq-writer` | `cloud_run_bq.tf` | Receives push from `pmp-events-to-bq-sub` → writes raw events to BigQuery |

> **Deployment note**: Cloud Run services are deployed via `gcloud run deploy` (see Makefile). Terraform defines their configuration for reference and IAM bindings, but actual images are pushed separately. See [docs/03-terraform-iac.md](../../docs/03-terraform-iac.md).

### Cloud Scheduler (`cloud_scheduler_*.tf`)

| Job | Schedule | Target |
| :--- | :--- | :--- |
| `pmp-velib-poll-every-minute` | `* * * * *` (every minute) | `pmp-velib-collector` `/collect` |
| `pmp-velib-station-info-daily` | `10 3 * * *` (daily 3:10 AM) | `pmp-velib-station-info-collector` `/collect` |

### IAM & Service Accounts (`iam.tf`)

| Service Account | Purpose | Key Roles |
| :--- | :--- | :--- |
| `pmp-dataflow-sa` | Dataflow streaming worker | Dataflow Worker, Pub/Sub Subscriber/Viewer, BigQuery DataEditor (curated + ops), Storage ObjectAdmin (bucket-scoped) |
| `pmp-collector-sa` | Cloud Run collector | Pub/Sub Publisher (events + station-info topics) |
| `pmp-station-info-writer-sa` | Station info writer | BigQuery DataEditor (curated) |
| `pmp-pubsub-push-sa` | Pub/Sub push invoker | Cloud Run Invoker (writer + bq-writer services), BigQuery DataEditor (raw) |
| `pmp-scheduler-sa` | Cloud Scheduler trigger | Cloud Run Invoker (collector services) |

> **Least Privilege**: All BigQuery permissions are scoped to dataset-level, not project-level. Storage permissions are scoped to the specific Dataflow bucket.

### Storage (`storage.tf`)
- **Bucket**: `gs://pmp-dataflow-paris-mobility-pulse` — Dataflow staging/temp files with 7-day lifecycle cleanup.

### Secrets (`secrets.tf`)
- **Placeholder**: `pmp-api-key-placeholder` — prepared for future API key management via Secret Manager.

---

## Prerequisites

- **Terraform**: `>= 1.5`
- **Google Cloud SDK**: Installed and authenticated.

### Authentication

```bash
gcloud auth application-default login
gcloud config set project paris-mobility-pulse
```

If you encounter `401 Anonymous caller` errors:
```bash
gcloud auth login --update-adc
```

---

## Quick Start

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

> Variables `project_id` and `region` default to `paris-mobility-pulse` and `europe-west9` (see `variables.tf` / `terraform.tfvars`).

---

## Import Existing Resources

If resources were created manually before Terraform, import them into state.

**Prerequisite**: Run `terraform init` first.

### Core Pipeline

```bash
# 1. GCS Staging Bucket
terraform import google_storage_bucket.dataflow_bucket pmp-dataflow-paris-mobility-pulse

# 2. BigQuery Datasets
terraform import google_bigquery_dataset.pmp_raw projects/paris-mobility-pulse/datasets/pmp_raw
terraform import google_bigquery_dataset.pmp_curated projects/paris-mobility-pulse/datasets/pmp_curated
terraform import google_bigquery_dataset.pmp_marts projects/paris-mobility-pulse/datasets/pmp_marts
terraform import google_bigquery_dataset.pmp_ops projects/paris-mobility-pulse/datasets/pmp_ops

# 3. BigQuery Tables (Curated)
terraform import google_bigquery_table.velib_station_status projects/paris-mobility-pulse/datasets/pmp_curated/tables/velib_station_status
terraform import google_bigquery_table.velib_station_information projects/paris-mobility-pulse/datasets/pmp_curated/tables/velib_station_information

# 4. BigQuery Tables (Raw + DLQ)
terraform import google_bigquery_table.velib_station_status_raw projects/paris-mobility-pulse/datasets/pmp_raw/tables/velib_station_status_raw
terraform import google_bigquery_table.velib_dlq_raw projects/paris-mobility-pulse/datasets/pmp_ops/tables/velib_dlq_raw
terraform import google_bigquery_table.velib_station_status_curated_dlq projects/paris-mobility-pulse/datasets/pmp_ops/tables/velib_station_status_curated_dlq

# 5. BigQuery Views (Marts)
terraform import google_bigquery_table.velib_latest_state projects/paris-mobility-pulse/datasets/pmp_marts/tables/velib_latest_state
terraform import google_bigquery_table.velib_station_information_latest projects/paris-mobility-pulse/datasets/pmp_marts/tables/velib_station_information_latest
terraform import google_bigquery_table.velib_latest_state_enriched projects/paris-mobility-pulse/datasets/pmp_marts/tables/velib_latest_state_enriched

# 6. Pub/Sub Topic + Subscriptions
terraform import google_pubsub_topic.pmp_events projects/paris-mobility-pulse/topics/pmp-events
terraform import google_pubsub_subscription.dataflow_sub projects/paris-mobility-pulse/subscriptions/pmp-events-dataflow-sub
terraform import google_pubsub_subscription.pmp_events_sub projects/paris-mobility-pulse/subscriptions/pmp-events-sub
terraform import google_pubsub_subscription.pmp_events_to_bq_sub projects/paris-mobility-pulse/subscriptions/pmp-events-to-bq-sub

# 7. Service Accounts
terraform import google_service_account.dataflow_sa projects/paris-mobility-pulse/serviceAccounts/pmp-dataflow-sa@paris-mobility-pulse.iam.gserviceaccount.com
terraform import google_service_account.collector_sa projects/paris-mobility-pulse/serviceAccounts/pmp-collector-sa@paris-mobility-pulse.iam.gserviceaccount.com
terraform import google_service_account.pubsub_push_sa projects/paris-mobility-pulse/serviceAccounts/pmp-pubsub-push-sa@paris-mobility-pulse.iam.gserviceaccount.com
terraform import google_service_account.scheduler_sa projects/paris-mobility-pulse/serviceAccounts/pmp-scheduler-sa@paris-mobility-pulse.iam.gserviceaccount.com
terraform import google_service_account.station_info_writer_sa projects/paris-mobility-pulse/serviceAccounts/pmp-station-info-writer-sa@paris-mobility-pulse.iam.gserviceaccount.com
```

### Station Information Pipeline

```bash
# 8. Pub/Sub (Station Info + DLQ)
terraform import google_pubsub_topic.station_info_topic projects/paris-mobility-pulse/topics/pmp-velib-station-info
terraform import google_pubsub_topic.station_info_dlq_topic projects/paris-mobility-pulse/topics/pmp-velib-station-info-push-dlq
terraform import google_pubsub_subscription.station_info_push_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-to-bq-sub
terraform import google_pubsub_subscription.station_info_dlq_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-push-dlq-hold-sub
terraform import google_pubsub_subscription.station_info_dlq_bq_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-push-dlq-to-bq-sub

# 9. Cloud Scheduler Jobs
terraform import google_cloud_scheduler_job.velib_poll_every_minute projects/paris-mobility-pulse/locations/europe-west1/jobs/pmp-velib-poll-every-minute
terraform import google_cloud_scheduler_job.station_info_daily projects/paris-mobility-pulse/locations/europe-west1/jobs/pmp-velib-station-info-daily
```

---

## Validation After Apply

```bash
# BigQuery datasets
bq ls --project_id=paris-mobility-pulse

# Curated table schema
bq show --format=prettyjson paris-mobility-pulse:pmp_curated.velib_station_status

# Pub/Sub subscriptions
gcloud pubsub subscriptions list --project=paris-mobility-pulse

# Terraform outputs
terraform output
```

---

## Cost Control

- **Bucket Lifecycle**: Objects under `temp/` and `staging/` are auto-deleted after 7 days.
- **Dataflow Job**: Streaming job runs until cancelled — not managed by Terraform. Use `pmpctl.sh demo-down` or cancel manually:
    ```bash
    gcloud dataflow jobs list --project="paris-mobility-pulse" --region="europe-west9" --status=active
    gcloud dataflow jobs cancel JOB_ID --project="paris-mobility-pulse" --region="europe-west9"
    ```
- **Cloud Scheduler**: Schedulers can be paused via `pmpctl.sh` to stop collection when the demo is inactive.

---

## File Layout

```
infra/terraform/
├── apis.tf                            # API enablement
├── backend.tf                         # State backend config
├── bigquery.tf                        # Datasets, tables, views (raw/curated/marts/ops)
├── cloud_run_bq.tf                    # BQ writer service (raw ingestion)
├── cloud_run_station_info.tf          # Station info collector + writer services
├── cloud_run_velib_collector.tf       # Vélib status collector service
├── cloud_scheduler_station_info.tf    # Daily station info trigger
├── cloud_scheduler_station_status.tf  # Per-minute status collection trigger
├── dlq_table_schema.json              # DLQ table schema definition
├── iam.tf                             # Service accounts + IAM bindings
├── outputs.tf                         # Terraform outputs
├── provider.tf                        # Google provider config
├── pubsub.tf                          # Topics + subscriptions (events, station-info, DLQ)
├── secrets.tf                         # Secret Manager placeholder
├── storage.tf                         # GCS bucket for Dataflow
├── variables.tf                       # Input variables
├── versions.tf                        # Required provider versions
└── gcloud-export/                     # Reference exports from gcloud (read-only)
```

---

## What's NOT in Terraform

| Resource | Why | Managed By |
| :--- | :--- | :--- |
| Dataflow streaming job | Launched via CLI/Python SDK; future: Flex Templates | `pmpctl.sh` / manual CLI |
| Cloud Run container images | Built and pushed via `gcloud builds submit` | Makefile |
| dbt views (`velib_totals_hourly_*`) | Business logic belongs in dbt, not IaC | `dbt run` (Makefile) |
| Budget alerts | Created via Console | GCP Console |
