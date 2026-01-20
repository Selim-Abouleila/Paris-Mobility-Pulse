# File: docs/00-bootstrap.md

# Bootstrap & Prerequisites

## 1. Prerequisites
- **Cloud Shell** (Recommended) or local terminal with `gcloud` and `bq` installed.
- **Google Cloud Project** created (ID: `paris-mobility-pulse`).
- **Billing enabled** for the project.
- **Active configuration**:
  ```bash
  gcloud config set project paris-mobility-pulse
  gcloud auth login  # If running locally
  ```

## 2. Enable APIs
Enable the necessary GCP services:

```bash
gcloud services enable \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  pubsub.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  bigquery.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com
```

## 3. Cost Control
> [!IMPORTANT]
> **Set a Budget Alert**: Go to [Billing](https://console.cloud.google.com/billing) > Budgets & alerts. Create a monthly budget (e.g., $10) and enable email alerts at 50%, 90%, and 100%.

> [!TIP]
> **Pause Scheduler**: When not demoing or developing, pause the Cloud Scheduler job to stop ingestion and save costs.
> ```bash
> gcloud scheduler jobs pause velib-poll-every-minute --location=europe-west1
> ```

## 4. BigQuery Setup

### Create Dataset
Create the raw dataset in the `europe-west9` region (to match Cloud Run co-location best practices, though BigQuery is often multi-region EU is fine too. Using default EU multi-region for simplicity if not specified, but let's stick to project defaults).

```bash
bq --location=EU mk -d paris-mobility-pulse:pmp_raw
```

### Create Table
Create the `velib_station_status_raw` table with the required schema.

Schema definition:
- `ingest_ts`: TIMESTAMP
- `event_ts`: TIMESTAMP
- `source`: STRING
- `event_type`: STRING
- `key`: STRING
- `payload`: JSON

Run:
```bash
bq mk --table \
  --time_partitioning_field=ingest_ts \
  --time_partitioning_type=DAY \
  paris-mobility-pulse:pmp_raw.velib_station_status_raw \
  ingest_ts:TIMESTAMP,event_ts:TIMESTAMP,source:STRING,event_type:STRING,key:STRING,payload:JSON
```

### Verification
Check if the table exists and is empty:
```bash
bq show paris-mobility-pulse:pmp_raw.velib_station_status_raw
bq query --use_legacy_sql=false 'SELECT count(*) FROM `paris-mobility-pulse.pmp_raw.velib_station_status_raw`'
```
