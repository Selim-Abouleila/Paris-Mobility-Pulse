# Operations: Demo Mode Control

The `scripts/pmpctl.sh` script provides one-command control over the cost-generating components of the Paris Mobility Pulse pipeline. This is the recommended way to start and stop the project for demos.

> [!IMPORTANT]
> **Project Targeting**: This script respects the `PROJECT_ID` defined in your `.env` file.
> *   If you want to control Prod: `PROJECT_ID=paris-mobility-pulse` in `.env`.
> *   If you want to control Dev: `PROJECT_ID=your-dev-project-id` in `.env`.
>
> If `.env` is missing, it defaults to `paris-mobility-pulse`, which will fail if you don't have permissions or if resources don't exist there.

## Purpose

To minimize Google Cloud costs, we only run the processing infrastructure when actively demoing or testing. On GCP, the main cost generators for this project are:

1.  **Cloud Scheduler Jobs**: These trigger ingestion (Vélib every minute, IDFM every 10 minutes).
2.  **Dataflow Streaming Jobs**: These keep worker VMs running.

The `pmpctl.sh` script automates pausing/resuming schedulers and starting/canceling Dataflow jobs.

### Managed Components

| Component | Type | Controlled by |
| :--- | :--- | :--- |
| `pmp-velib-poll-every-minute` | Cloud Scheduler | `up` / `down` |
| `pmp-velib-station-info-daily` | Cloud Scheduler | `up` / `down` |
| `idfm-poll-every-10min` | Cloud Scheduler | `up` / `down` |
| `pmp-velib-curated-*` | Dataflow streaming | `up` / `down` |
| `pmp-velib-collector` | Cloud Run (poke) | `collect` |
| `pmp-velib-station-info-collector` | Cloud Run (poke) | `collect` |
| `pmp-idfm-collector` | Cloud Run (poke) | `collect` |

> [!NOTE]
> Cloud Run services (collectors and writers) do **not** need to be started or stopped. They scale to zero and only cost money when they are processing a request.

## Main Commands

| Command | Action |
| :--- | :--- |
| `./scripts/pmpctl.sh status` | Show current state of schedulers and Dataflow jobs. |
| `./scripts/pmpctl.sh up` | **Start Demo**: Resume schedulers + Launch Dataflow streaming job. |
| `./scripts/pmpctl.sh collect` | **Poke**: Manually trigger all collectors once — Vélib + IDFM (bypasses scheduler). |
| `./scripts/pmpctl.sh down` | **Stop Demo**: Pause all schedulers + Cancel Dataflow streaming job(s). |

## Usage Examples

### 1. Check current status
```bash
./scripts/pmpctl.sh status
```

### 2. Start the pipeline for a demo
```bash
./scripts/pmpctl.sh up
```
*Submission logs are saved to `logs/dataflow_pmp-velib-curated-*.log`.*

### 3. Trigger data ingestion immediately (all collectors)
```bash
./scripts/pmpctl.sh collect
# Pokes: pmp-velib-collector, pmp-velib-station-info-collector, pmp-idfm-collector
```

### 4. Shut down all cost-generating resources
```bash
./scripts/pmpctl.sh down
```

## Supported Environment Overrides

The script uses defaults from `infra/terraform` but can be overridden by exporting environment variables:

- `PROJECT_ID`: GCP Project (default: `paris-mobility-pulse`)
- `REGION`: Main compute region (default: `europe-west9`)
- `SCHED_LOCATION`: Region for Cloud Scheduler (default: `europe-west1`)
- `BUCKET`: GCS bucket for Dataflow (default: `gs://pmp-dataflow-${PROJECT_ID}`)
- `INPUT_SUB`: Pub/Sub input sub (default: `projects/${PROJECT_ID}/subscriptions/pmp-events-dataflow-sub`)
- `OUT_TABLE`: BigQuery output table (default: `${PROJECT_ID}:pmp_curated.velib_station_status`)
- `DATAFLOW_SA`: Service Account for Dataflow (default: `pmp-dataflow-sa@${PROJECT_ID}.iam.gserviceaccount.com`)

## Troubleshooting

### Error: "Anonymous caller" or "401"
If Dataflow or GCS commands fail with authentication errors, refresh your Application Default Credentials:
```bash
gcloud auth application-default login
gcloud auth login --update-adc
```

### Scheduler Job Not Found
If the script fails to find scheduler jobs, ensure `SCHED_LOCATION` matches where your jobs are deployed (usually `europe-west1`).

### Logs
- **Dataflow Submission**: Check `logs/` directory for local submission output.
- **Service Logs**: Use `gcloud run services logs read <service-name>`.

## Cost Safety
- **Streaming Dataflow**: Costs money as long as the job is `Running`. Always run `./scripts/pmpctl.sh down` when your demo session is over.
- **Automated Pausing**: By pausing all schedulers (Vélib + IDFM), we stop the continuous flow of events even if the Cloud Run services remain deployed.
- **IDFM Collector**: Writes directly to BigQuery (no Dataflow needed). Cost is minimal — only BigQuery streaming insert charges (~$0.01 per 200 MB).
