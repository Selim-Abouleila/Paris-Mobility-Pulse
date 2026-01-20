# File: docs/02-ops-troubleshooting.md

# Operations & Troubleshooting

## 1. Manage Ingestion

**Stop Ingestion (Save Cost/Pause)**:
```bash
gcloud scheduler jobs pause velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

**Resume Ingestion**:
```bash
gcloud scheduler jobs resume velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

**Run Once (Manual Trigger)**:
```bash
gcloud scheduler jobs run velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

## 2. Key Log Queries

**Writer Requests** (Check specific `/pubsub` endpoint hits):
```bash
gcloud logging read \
'resource.type="cloud_run_revision"
 resource.labels.service_name="pmp-bq-writer"
 httpRequest.requestUrl:"/pubsub"' \
 --project="paris-mobility-pulse" \
 --limit=20 \
 --format='table(timestamp,httpRequest.status)'
```

**Writer Errors** (Application level logs):
```bash
gcloud logging read \
'resource.type="cloud_run_revision"
 resource.labels.service_name="pmp-bq-writer"
 severity>=ERROR' \
 --project="paris-mobility-pulse" \
 --limit=10
```

## 3. Common Issues & Fixes

### Push Subscription Endpoint Misconfigured
**Symptom**: Messages pile up in subscription, writer logs show no incoming requests.
**Cause**: Endpoint might be a placeholder or missing `/pubsub` suffix.
**Fix**:
Update subscription with correct URL:
```bash
gcloud pubsub subscriptions update pmp-events-to-bq-sub \
  --push-endpoint=https://[ACTUAL-WRITER-URL]/pubsub
```

### BigQuery Insertion Error: "Field value ... cannot be empty"
**Symptom**: Writer 500s or logs error about `event_ts`.
**Cause**: Incoming JSON payload might miss `event_ts`.
**Fix**: Ensure your Writer code defaults `event_ts` to `ingest_ts` (current time) if the field is missing.

### Docker Build Fails
**Symptom**: `COPY failed: file not found in build context or excluded`.
**Cause**: Mismatch in `requirements.txt` filename or location.
**Fix**: Check `Dockerfile` vs actual filename.

### gcloud "No active account selected"
**Symptom**: Command failure.
**Fix**:
```bash
gcloud auth login
gcloud config set project paris-mobility-pulse
```

### BigQuery Stale Data
**Symptom**: `COUNT(*)` doesn't increase despite successful writes.
**Cause**: Cached query results.
**Fix**: Use `--nouse_cache` flag.

> [!CAUTION]
> **Safety Note**: If you encounter a "retry storm" (many 500 errors causing Pub/Sub to retry endlessly), **pause the scheduler** immediately to stop adding fuel to the fire while you debug.
