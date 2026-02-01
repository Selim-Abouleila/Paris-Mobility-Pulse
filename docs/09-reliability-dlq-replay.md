# 09 - Reliability: DLQ + Replay

> [!NOTE]
> **Status**
> ✅ **Implemented today**: DLQ topic, `dead_letter_policy`, hold subscription, BQ export subscription, and table created with metadata enabled.
> ✅ **Verified end-to-end**: Successfully performed E2E dead-lettering drill via writer failure injection.
> ⏳ **Planned next**: Apply pattern to `pmp-events-to-bq-sub`, Dataflow DLQ side outputs, replay worker automation, and unified monitoring dashboard.

## 1. Goal & Reliability Semantics
This document defines the reliability strategy for the **push subscription** path of `station-info`. Because `station-info` is a low-frequency feed (typically once per day), the Dead Letter Queue (DLQ) remains empty during normal operations. Its presence is strictly for capturing "poison pills" or systemic downstream failures.

### How it Works
1. **Push Delivery**: Pub/Sub pushes messages to the Cloud Run writer via HTTP.
2. **ACK/NACK Logic**: A push subscription only acknowledges (ACKs) if the endpoint returns an **HTTP 2xx** status code. 
3. **Retries & DLQ**: Any non-2xx response (or timeout) triggers a retry. After approximately `maxDeliveryAttempts` (5 in our setup), Pub/Sub forwards the message to the **DLQ Topic**.
4. **Best-Effort Delivery**: Note that delivery attempts are approximate; Pub/Sub provides at-least-once delivery semantics.
5. **Metadata Wrapping**: Forwarded messages include `CloudPubSubDeadLetter...` attributes identifying the source.

## 2. Architecture
We maintain two distinct paths for dead-lettered messages to balance speed and auditability.

```text
[ pmp-velib-station-info ] (Original Topic)
       |
       v
[ pmp-velib-station-info-to-bq-sub ] -- (NACK / 500) --> [ Cloud Run Writer ]
       |
       | (After 5 attempts)
       v
[ pmp-velib-station-info-push-dlq ] (DLQ Topic)
       |
       +-----> [ pmp-velib-station-info-push-dlq-hold-sub ] 
       |       (7-day retention | Buffer for manual inspection & local replay)
       |
       +-----> [ pmp-velib-station-info-push-dlq-to-bq-sub ] 
               (BQ Export | Permanent audit trail for pattern analysis)
                      |
                      v
               [ BQ Dataset: pmp_ops ] -> [ Table: velib_station_info_push_dlq ]
```

## 3. Data Model
### BigQuery Table: `paris-mobility-pulse.pmp_ops.velib_station_info_push_dlq`
**Dataset Location**: TODO: europe-west9 (Run `bq show --format=prettyjson paris-mobility-pulse:pmp_ops | jq -r .location` to verify).

| Column | Type | Description |
| :--- | :--- | :--- |
| `subscription_name` | STRING | ID of the source subscription (`pmp-velib-station-info-to-bq-sub`). |
| `message_id` | STRING | Unique Pub/Sub message ID. |
| `publish_time` | TIMESTAMP | Original publish time. Requires `write_metadata=true` for partitioning. |
| `data` | STRING | Raw message payload. |
| `attributes` | STRING | JSON-serialized metadata (includes DLQ specific headers). |

### Proof of Life: Observed DLQ Attributes
Verified drill evidence stored in BQ:
```json
{
  "CloudPubSubDeadLetterSourceDeliveryCount": "5",
  "CloudPubSubDeadLetterSourceSubscription": "pmp-velib-station-info-to-bq-sub",
  "source": "e2e_test",
  "dlq_test": "true"
}
```

### Analysis SQL Example
To extract DLQ metadata from the `attributes` string:
```sql
SELECT 
  publish_time,
  JSON_EXTRACT_SCALAR(attributes, '$.CloudPubSubDeadLetterSourceDeliveryCount') as attempts,
  JSON_EXTRACT_SCALAR(attributes, '$.CloudPubSubDeadLetterSourceSubscription') as origin,
  data
FROM `paris-mobility-pulse.pmp_ops.velib_station_info_push_dlq`
ORDER BY publish_time DESC;
```

## 4. Verification & E2E Drill
We do not wait for errors to happen; we validate via controlled drills using a failure injection mechanism in the writer service.

### Test A: Sanity Check (Direct)
Confirm BQ export is healthy by bypassing the source subscription.
```bash
gcloud pubsub topics publish pmp-velib-station-info-push-dlq \
  --message='{"test": "sanity_check"}'
```

### Test B: True E2E Dead-Lettering Drill
1. **Enable Failure Injection**: Toggle the environment variable on the writer.
   ```bash
   # Run this to enable (WARNING: Do NOT leave enabled in prod)
   gcloud run services update station-info-writer \
     --update-env-vars DLQ_TEST_ENABLED=true \
     --region=TODO:REGION
   ```
2. **Publish Drill Message**: Trigger the failure path.
   ```bash
   gcloud pubsub topics publish pmp-velib-station-info \
     --attribute="dlq_test=true,source=e2e_test" \
     --message='{"test": "reliability_drill"}'
   ```
3. **Monitor & Confirm**: Wait ~1-2 minutes for retries to exhaust. Confirm in BQ:
   ```bash
   bq query --use_legacy_sql=false \
   'SELECT * FROM `paris-mobility-pulse.pmp_ops.velib_station_info_push_dlq` WHERE attributes LIKE "%e2e_test%"'
   ```
4. **Cleanup**: Disable the injection switch immediately.
   ```bash
   gcloud run services update station-info-writer \
     --update-env-vars DLQ_TEST_ENABLED=false \
     --region=TODO:REGION
   ```

## 5. Terraform Infrastructure
Manage the DLQ stack with `lifecycle { prevent_destroy = true }` for topics and BQ tables.

### Resources
- `google_pubsub_topic.pmp-velib-station-info-push-dlq`
- `google_pubsub_subscription.pmp-velib-station-info-push-dlq-hold-sub`
- `google_pubsub_subscription.pmp-velib-station-info-push-dlq-to-bq-sub` (config: `bigquery_config.write_metadata = true`)
- `google_bigquery_table.velib_station_info_push_dlq`

### IAM Requirements
The **Pub/Sub Service Agent** (`service-{PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com`) requires:
- `roles/pubsub.publisher` on the **DLQ Topic**.
- `roles/pubsub.subscriber` on the **Source Subscription**.
- `roles/bigquery.dataEditor` and `roles/bigquery.metadataViewer` on the `pmp_ops` dataset.

### Import Commands
```bash
terraform import google_pubsub_topic.dlq_topic projects/paris-mobility-pulse/topics/pmp-velib-station-info-push-dlq
terraform import google_pubsub_subscription.dlq_hold_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-push-dlq-hold-sub
terraform import google_pubsub_subscription.dlq_bq_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-push-dlq-to-bq-sub
terraform import google_bigquery_table.dlq_table projects/paris-mobility-pulse/datasets/pmp_ops/tables/velib_station_info_push_dlq
```

## 6. Monitoring
For `station-info`, "Good" is typically zero.

| Metric | "Good" | "Bad" | Rationale |
| :--- | :--- | :--- | :--- |
| `dead_letter_message_count` | 0 | > 0 | Indicates any message failed all retries. |
| `num_undelivered_messages` (DLQ) | 0 | > 0 | Stuck messages in the hold sub or BQ export failure. |

### SQL Weekly Trend
```sql
SELECT 
  TIMESTAMP_TRUNC(publish_time, DAY) as day,
  COUNT(*) as failures
FROM `paris-mobility-pulse.pmp_ops.velib_station_info_push_dlq`
WHERE publish_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY 1 ORDER BY 1 DESC;
```

## 7. Troubleshooting
- **Messages repeat in Hold Subscription**: Using `gcloud pubsub subscriptions pull` without `--auto-ack` keeps the message in the queue. Use `--auto-ack` or manual ACK if you intend to clear it.
- **`publish_time`/`attributes` are NULL**: This occurs if the BQ export sub was created/configured *before* `write_metadata` was enabled. Only new messages arriving after the fix will have metadata.
- **IAM Permission Denied**: If `dead_letter_message_count` is > 0 but the DLQ topic/table is empty, the service agent lacks `publisher` permission on the DLQ topic.
