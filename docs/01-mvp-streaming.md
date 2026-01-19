# MVP Streaming Pipeline (Step 1–2)

## Step 1 — Collector (Cloud Run → Pub/Sub)

### Create Pub/Sub topic
```bash
gcloud pubsub topics create pmp-events --project=paris-mobility-pulse
```

### Deploy collector to Cloud Run

**Service:** `pmp-velib-collector`  
**Endpoint:** `GET /collect`  
**Publishes to topic:** `pmp-events`

Example deploy:

```bash
gcloud run deploy pmp-velib-collector \
  --source ./collectors/velib \
  --region europe-west9 \
  --service-account pmp-collector-sa@paris-mobility-pulse.iam.gserviceaccount.com \
  --set-env-vars "TOPIC_ID=pmp-events,FEED_URL=https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_status.json,SOURCE=velib,EVENT_TYPE=station_status_snapshot" \
  --no-allow-unauthenticated
```

### Schedule it

Cloud Scheduler calls `/collect` every minute.

(See `docs/02-ops-runbook.md` for pause/resume commands.)

## Step 2 — Writer (Pub/Sub push → Cloud Run → BigQuery)

### BigQuery table (raw)

**Dataset:** `pmp_raw`  
**Table:** `velib_station_status_raw`

**Schema:**
- `ingest_ts` TIMESTAMP
- `event_ts` TIMESTAMP
- `source` STRING
- `event_type` STRING
- `key` STRING
- `payload` JSON

**Partition:**
Partition by `ingest_ts` (by day)

### Deploy writer to Cloud Run

**Service:** `pmp-bq-writer`  
**Endpoint:** `POST /pubsub`

```bash
gcloud run deploy pmp-bq-writer \
  --source ./services/bq-writer \
  --region europe-west9 \
  --service-account pmp-bq-writer-sa@paris-mobility-pulse.iam.gserviceaccount.com \
  --set-env-vars "BQ_DATASET=pmp_raw,BQ_TABLE=velib_station_status_raw" \
  --no-allow-unauthenticated
```

### Configure Pub/Sub push subscription to writer

**Subscription:** `pmp-events-to-bq-sub`  
**Push endpoint:** `{WRITER_URL}/pubsub`  
**Audience:** `{WRITER_URL}`  
**Push service account:** `pmp-pubsub-push-sa@paris-mobility-pulse.iam.gserviceaccount.com`

Validate the pushConfig:

```bash
gcloud pubsub subscriptions describe pmp-events-to-bq-sub \
  --project=paris-mobility-pulse \
  --format="yaml(pushConfig)"
```

### Verification queries

```sql
SELECT COUNT(*) AS row_count
FROM `paris-mobility-pulse.pmp_raw.velib_station_status_raw`;

SELECT ingest_ts, event_ts, source, event_type, key
FROM `paris-mobility-pulse.pmp_raw.velib_station_status_raw`
ORDER BY ingest_ts DESC
LIMIT 20;
```
