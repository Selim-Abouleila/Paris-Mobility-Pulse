# Paris Mobility Pulse (Streaming Data Engineering on GCP)

Real-time pipeline that ingests Paris mobility signals (starting with Vélib station_status), processes events in near real-time, and stores them in BigQuery for analytics.

## Architecture

![Pipeline architecture](docs/images/pipeline.png)

## What’s implemented
- Cloud Run collector (`pmp-velib-collector`) polls Vélib station_status and publishes JSON events to Pub/Sub (Publish/Subscribe).
- Cloud Run writer (`pmp-bq-writer`) receives Pub/Sub (Publish/Subscribe) push messages and inserts into BigQuery raw table.
- Dataflow (Google Cloud Dataflow) streaming (Apache Beam) reads from `pmp-events-dataflow-sub`, validates + dedups, and writes curated rows to `pmp_curated.velib_station_status`.
- BigQuery Marts layer (`pmp_marts`) provides dashboard-ready views (e.g., `velib_latest_state`).
- Looker Studio Dashboard for real-time visualization and trends.

## Key GCP resources
- **BigQuery**:
    - **Raw Layer** (`pmp_raw`): Landing zone for JSON payloads.
    - **Curated Layer** (`pmp_curated`):
        - `velib_station_status`: History of station updates.
        - `velib_station_information`: Static metadata (names, capacity).
    - **Marts Layer** (`pmp_marts`):
        - `velib_latest_state`: Real-time snapshot (View).
        - `velib_latest_state_enriched`: Latest state + metadata (View).
        - `velib_totals_hourly`: Aggregated trends for dashboarding (Materialized View).
        - `velib_totals_hourly_paris`: Timezone-adjusted wrapper (View).
    - **Ops Layer** (`pmp_ops`):
        - `velib_station_info_push_dlq`: Dead-letter queue messages for replay/audit.
- **Pub/Sub**:
    - **Topics**: `pmp-events` (Real-time status), `pmp-velib-station-info` (Daily metadata), `pmp-velib-station-info-push-dlq` (Dead Letter Queue).
    - **Subscriptions**:
        - `pmp-events-dataflow-sub`: Streaming pull for Dataflow.
        - `pmp-events-sub`: Debugging/Audit.
        - `pmp-events-to-bq-sub`: Push subscription for MVP (Cloud Run).
        - `pmp-velib-station-info-to-bq-sub`: Push subscription for Station Info (Cloud Run).
        - `pmp-velib-station-info-push-dlq-hold-sub`: 7-day retention for replay.
        - `pmp-velib-station-info-push-dlq-to-bq-sub`: Export to BigQuery (`pmp_ops`).
- **Dataflow**: `pmp-velib-curated` (Streaming ETL).
- **Cloud Run**:
    - `pmp-velib-collector`: Polls real-time station status.
    - `pmp-bq-writer`: Ingests JSON events into BigQuery.
    - `pmp-velib-station-info-collector`: Polls static station metadata (Daily).
    - `pmp-velib-station-info-writer`: Ingests metadata into BigQuery.
- **Cloud Scheduler**:
    - `velib-poll-every-minute` (Every minute): Triggers status collection.
    - `pmp-velib-station-info-daily` (Daily at 03:10): Triggers daily metadata refresh.

## Dashboards

**Vélib Dashboard v1** visualizes real-time station status and hourly availability trends using Looker Studio.

[**View Dashboard**](https://lookerstudio.google.com/reporting/40ae9759-385b-4b7f-9248-325390e3c5df)

![Vélib Dashboard v1](images/pmp_velib_dash_1.png)

See [08 - Vélib Dashboard](./docs/08-velib-dashboard.md) for details on data sources and metrics.

## Operations (Demo Mode)

The project includes a control script to safely start/stop the pipeline and manage costs. This is the **most practical way** to run the pipeline for demos.

```bash
./scripts/pmpctl.sh status   # Show current state
./scripts/pmpctl.sh up       # Start ingestion + Dataflow
./scripts/pmpctl.sh collect  # Trigger collectors once
./scripts/pmpctl.sh down     # Stop all cost-generating resources
```
See [07 - Operations: Demo Control](./docs/07-operations-demo-control.md) for details.

## Cost control (Manual)

Pause ingestion when not demoing:

```bash
gcloud scheduler jobs pause velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

Resume:

```bash
gcloud scheduler jobs resume velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

## Budget Alert (Cost Guardrail)

A monthly budget alert is configured at **$40/month** to provide a safety guardrail for demo activities and prevent accidental spend. This budget alert complements the project's operational stop controls; see [07 - Operations: Demo Control](./docs/07-operations-demo-control.md) for instructions on pausing or stopping cost-generating resources.

![Budget alert screenshot](images/budget_alert.png)

## Dataflow: Pub/Sub → Curated BigQuery (Streaming)

### Disclaimer: Dataflow is optional for this MVP

This curated table could have been produced without Dataflow by **Cloud Run writer directly flattening to pmp_curated** or **BigQuery SQL (views/materialized views) over pmp_raw**.

Dataflow was chosen because it demonstrates **"Professional Data Engineer" streaming patterns** and sets up safeguards for future complexity (dedup, windowing, DLQ, replay).

**Cost note**: Streaming Dataflow jobs have ongoing cost, so for future pipelines we prefer non-Dataflow approaches unless needed.

See [docs/04-dataflow-curation.md](docs/04-dataflow-curation.md) for the full rationale and tradeoffs.

Run the Apache Beam pipeline on DataflowRunner to write curated rows to BigQuery.

### Prerequisites

1. **Authenticated Google Cloud SDK**:
   - `gcloud auth login`
   - `gcloud auth application-default login`
   - **Fix**: Run `gcloud auth login --update-adc` if `gsutil` or Dataflow complains about "Anonymous caller".
2. **Environment**:
   - Bucket accessible: `gs://pmp-dataflow-paris-mobility-pulse`
   - APIs enabled: Dataflow, Pub/Sub, BigQuery.
   - Project dependencies: `pip install -r pipelines/dataflow/pmp_streaming/requirements.txt`

### Run the Pipeline

```bash
PROJECT_ID="paris-mobility-pulse"
REGION="europe-west9"
BUCKET="gs://pmp-dataflow-${PROJECT_ID}"
INPUT_SUB="projects/${PROJECT_ID}/subscriptions/pmp-events-dataflow-sub"
OUT_TABLE="${PROJECT_ID}:pmp_curated.velib_station_status"

python3 -m pipelines.dataflow.pmp_streaming.main \
  --runner DataflowRunner \
  --allow_dataflow_runner \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --temp_location "$BUCKET/temp" \
  --staging_location "$BUCKET/staging" \
  --job_name "pmp-velib-curated-$(date +%Y%m%d-%H%M%S)" \
  --service_account_email "pmp-dataflow-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --streaming \
  --input_subscription "$INPUT_SUB" \
  --output_bq_table "$OUT_TABLE" \
  --setup_file ./setup.py \
  --requirements_file pipelines/dataflow/pmp_streaming/requirements.txt \
  --num_workers 1 \
  --max_num_workers 1 \
  --autoscaling_algorithm=NONE \
  --save_main_session
```

### Verification

**1. List Jobs**
```bash
gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION"
```

**2. Query BigQuery (Curated)**
Ensure rows are arriving (disable cache if needed):
```sql
SELECT * FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
ORDER BY ingest_ts DESC
LIMIT 20
```

**3. Test Publish (Optional)**
Publish a single station message to `pmp-events`:
```bash
gcloud pubsub topics publish pmp-events --project="$PROJECT_ID" --message='{"ingest_ts":"2026-01-24T16:00:00Z","event_ts":"2026-01-24T16:00:00Z","source":"velib","event_type":"station_status_snapshot","key":"test:one_station","payload":{"data":{"stations":[{"station_id":123,"stationCode":"X1","is_installed":1,"is_renting":1,"is_returning":1,"last_reported":1768918344,"num_bikes_available":5,"num_docks_available":10,"num_bikes_available_types":[{"mechanical":3},{"ebike":2}]}]}}}'
```

### Stop the Job

The pipeline runs until cancelled.

**CLI:**
```bash
gcloud dataflow jobs cancel JOB_ID --project="$PROJECT_ID" --region="$REGION"
```
*(Replace `JOB_ID` with the ID from the list command)*

**Console:**
Dataflow → Jobs → Select job → **Stop / Cancel**.

## Documentation

Detailed guides for each component:
- [00 - Bootstrap](docs/00-bootstrap.md) - Initial project setup
- [01 - MVP Pipeline](docs/01-mvp-pipeline.md) - Cloud Run ingestion setup
- [02 - Ops & Troubleshooting](docs/02-ops-troubleshooting.md) - Operational procedures
- [03 - Terraform IAC](docs/03-terraform-iac.md) - Infrastructure as Code setup
- [04 - Dataflow Curation](docs/04-dataflow-curation.md) - Streaming processing pipeline
- [05 - BigQuery Marts](docs/05-bigquery-marts-latest-state.md) - Analytics layer and latest state views
- [06 - Vélib Station Information Pipeline](docs/06-velib-station-information-pipeline.md) - Static station metadata collection
- [07 - Operations: Demo Control](docs/07-operations-demo-control.md) - Automated demo lifecycle management
- [08 - Vélib Dashboard](docs/08-velib-dashboard.md) - Looker Studio report and metrics
- [09 - Reliability: DLQ + Replay](docs/09 - Reliability - DLQ + Replay.md) - Dead Letter Queue and Replay strategy

## Next milestone

- Add Dataflow for validation/dedup/windowed aggregates + DLQ.

## Development

To maintain code quality, please run the following commands before pushing:

### Installation
```bash
make install
```

### Formatting
```bash
make fmt    # Format code (ruff + terraform)
make check  # Check formatting and linting
```
