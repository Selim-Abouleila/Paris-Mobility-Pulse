# Station-Info DLQ Replayer

A Cloud Run Job to replay messages from the `station-info` Push DLQ hold subscription back to the original topic.

## Design

- **Batch Processing**: Pulls messages in batches of 10.
- **Loop Prevention**: Filters out messages already tagged with `replay=true`.
- **Attribute Cleaning**: Removes GCR-injected DLQ headers (`CloudPubSubDeadLetter*`).
- **Metadata**: Injects `replay=true`, `replay_id`, and `replay_source` into replayed messages.
- **Rate Limiting**: Respects a `QPS` (Queries Per Second) limit to avoid overwhelming the destination.

## Configuration (Env Vars)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PROJECT_ID` | `paris-mobility-pulse` | GCP Project ID. |
| `DLQ_SUB` | `...-dlq-hold-sub` | Full path of the DLQ hold subscription. |
| `DEST_TOPIC` | `...-station-info` | Full path of the destination topic. |
| `MAX_MESSAGES` | `50` | Stop after processing this many messages. |
| `BATCH_SIZE` | `10` | Messages per Pub/Sub pull request. |
| `QPS` | `5` | Publish requests per second. Guards against `0`. |
| `PULL_TIMEOUT_S` | `10` | Timeout for pulling from Pub/Sub. |
| `PUBLISH_TIMEOUT_S` | `30` | Timeout for publishing to Pub/Sub. |
| `DRY_RUN` | `false` | If `true`, logs republish intent but does not publish or ACK. |
| `ACK_SKIPPED` | `false` | If `true`, ACKs messages that are skipped due to replay loops. |

## Deployment

### 1. Build & Push Image
```bash
IMAGE_TAG="gcr.io/paris-mobility-pulse/station-info-dlq-replayer"
gcloud builds submit --tag $IMAGE_TAG .
```

### 2. Create Cloud Run Job
```bash
gcloud run jobs create station-info-dlq-replayer \
  --image $IMAGE_TAG \
  --region europe-west9 \
  --service-account pmp-cloud-run-sa@paris-mobility-pulse.iam.gserviceaccount.com \
  --set-env-vars DRY_RUN=true
```

## Execution

### Run with Defaults
```bash
gcloud run jobs execute station-info-dlq-replayer --region europe-west9
```

### Run with Overrides (e.g., Live Replay of 100 messages)
```bash
gcloud run jobs execute station-info-dlq-replayer --region europe-west9 \
  --update-env-vars DRY_RUN=false,MAX_MESSAGES=100
```
