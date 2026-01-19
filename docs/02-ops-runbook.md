# Ops Runbook

## Pause / resume ingestion

**Pause Scheduler:**
```bash
gcloud scheduler jobs pause velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

**Resume:**
```bash
gcloud scheduler jobs resume velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

**Run once:**
```bash
gcloud scheduler jobs run velib-poll-every-minute --project=paris-mobility-pulse --location=europe-west1
```

## Debugging

**Check Pub/Sub delivery to writer**

```bash
gcloud logging read \
'resource.type="cloud_run_revision"
 resource.labels.service_name="pmp-bq-writer"
 httpRequest.requestUrl:"/pubsub"' \
 --project="paris-mobility-pulse" \
 --limit=20 \
 --format='table(timestamp,httpRequest.status)'
```

## Common error

**Field value of event_ts cannot be empty**
*   Fix: writer should default `event_ts = ingest_ts` when missing.
