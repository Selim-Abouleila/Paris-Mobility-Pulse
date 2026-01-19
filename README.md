# Paris Mobility Pulse (Streaming Data Engineering on GCP)

Real-time pipeline that ingests Paris mobility signals (starting with Vélib station_status), processes events in near real-time, and stores them in BigQuery for analytics.

## Architecture

![Pipeline architecture](docs/images/pipeline.png)

## What’s implemented (Step 1–2)
- Cloud Run collector (`pmp-velib-collector`) polls Vélib station_status and publishes JSON events to Pub/Sub.
- Cloud Run writer (`pmp-bq-writer`) receives Pub/Sub push messages and inserts into BigQuery raw table.
- Push subscription (`pmp-events-to-bq-sub`) delivers Pub/Sub messages to the writer.

## Key GCP resources
- Project: `paris-mobility-pulse`
- Region (Cloud Run): `europe-west9`
- Pub/Sub topic: `pmp-events`
- Push subscription: `pmp-events-to-bq-sub`
- BigQuery dataset: `pmp_raw`
- BigQuery table: `velib_station_status_raw`
- Scheduler job: `velib-poll-every-minute` (location: `europe-west1`)

## Quick validation
Check latest rows:

```sql
SELECT ingest_ts, event_ts, source, event_type, key
FROM `paris-mobility-pulse.pmp_raw.velib_station_status_raw`
ORDER BY ingest_ts DESC
LIMIT 20;
```

## Cost control

Pause ingestion when not demoing:

```bash
gcloud scheduler jobs pause velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

Resume:

```bash
gcloud scheduler jobs resume velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

## Next milestone

- Add Dataflow for validation/dedup/windowed aggregates + DLQ.
- Create curated tables (latest state + aggregates) for Looker Studio.
