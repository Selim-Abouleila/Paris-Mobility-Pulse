# Reliability: DLQ + Replay Strategy

## 1. Goal & Why DLQ Matters
In a production streaming pipeline, failures are inevitable (network blips, schema drift, upstream data corruption). The Dead Letter Queue (DLQ) pattern is critical for:
- **Reliability**: Prevents a single poisonous message from blocking the entire pipeline (Head-of-Line blocking).
- **Auditability**: Provides a permanent record of what failed, when, and why, without cluttering the main data tables.
- **Replayability**: Allows for "Correction of Errors" (CoE) by re-injecting failed data once the root cause is resolved.

## 2. Architecture & Resource Names
We implement a multi-stage DLQ pattern where failed messages are first diverted by Pub/Sub and then exported to BigQuery for long-term storage and analysis.

### ASCII Diagram
```text
[ Source Topic ] 
       |
[ Source Subscription ] -- (Max 5 attempts) --> [ Target Service (Writer) ]
       |                                              |
       | (on failure)                                 | (HTTP 4xx/5xx)
       v
[ DLQ Topic ] 
       |
       |------> [ DLQ Hold Subscription ] (7-day retention for manual replay)
       |
       |------> [ DLQ BigQuery Subscription ] (BigQuery Export)
                      |
                      v
               [ BQ Ops Dataset ] -> [ DLQ Table ]
```

### Exact Resource Names
- **Source Subscription**: `pmp-velib-station-info-to-bq-sub`
- **DLQ Topic**: `pmp-velib-station-info-push-dlq`
- **DLQ Hold Subscription**: `pmp-velib-station-info-push-dlq-hold-sub`
- **DLQ BigQuery Export Subscription**: `pmp-velib-station-info-push-dlq-to-bq-sub`
- **BigQuery Dataset**: `pmp_ops` (Location: TODO: europe-west9)
- **BigQuery Table**: `velib_station_info_push_dlq`

## 3. Data Model
The DLQ table in BigQuery uses a flexible schema to ensure that even "broken" data is successfully captured.

### Table Schema (`pmp_ops.velib_station_info_push_dlq`)
| Column | Type | Description |
| :--- | :--- | :--- |
| `subscription_name` | STRING | The ID of the subscription that moved the message to DLQ. |
| `message_id` | STRING | Unique Pub/Sub message ID. |
| `publish_time` | TIMESTAMP | Original publish timestamp (Used for **Partitioning**). |
| `data` | STRING | Raw message payload. Stored as **STRING** to prevent DLQ ingestion failure on JSON syntax errors. |
| `attributes` | JSON | Key-value metadata attached to the message. |

**Partitioning Strategy**: The table is partitioned by `publish_time` (DAY). This allows Ops to query failures for specific time windows without scanning the entire history.

## 4. Terraform Infrastructure
The DLQ stack is defined in the `infra/terraform/` directory.

### Key Resources
1. **Source Subscription Policy**: Configures `dead_letter_policy`.
   - File: `infra/terraform/pubsub.tf`
   ```hcl
   resource "google_pubsub_subscription" "station_info_push_sub" {
     # ...
     dead_letter_policy {
       dead_letter_topic     = google_pubsub_topic.station_info_dlq_topic.id
       max_delivery_attempts = 5
     }
   }
   ```
2. **DLQ BigQuery Export**: Uses the native BigQuery subscription type.
   - File: `infra/terraform/pubsub.tf`
   ```hcl
   resource "google_pubsub_subscription" "station_info_dlq_bq_sub" {
     name  = "pmp-velib-station-info-push-dlq-to-bq-sub"
     topic = google_pubsub_topic.station_info_dlq_topic.name
     bigquery_config {
       table          = "${var.project_id}.pmp_ops.velib_station_info_push_dlq"
       write_metadata = true
     }
   }
   ```
3. **IAM Bindings**: Essential for Pub/Sub to publish to DLQ and write to BQ.
   - File: `infra/terraform/pubsub.tf` & `bigquery.tf`
   - `roles/pubsub.publisher` for the Pub/Sub Service Agent on the DLQ Topic.
   - `roles/bigquery.dataEditor` for the Pub/Sub Service Agent on the `pmp_ops` dataset.

## 5. Runbook: Verification & Inspection

### Verify DLQ is working
To simulate a failure, you can publish a message that you know the consumer will reject, or push directly to the DLQ topic for testing:
```bash
gcloud pubsub topics publish pmp-velib-station-info-push-dlq \
  --message='{"test": "reliability_check", "status": "fail"}' \
  --attribute="origin=manual_test"
```

### Inspect Recent Failures
Run this query in the BigQuery console to see the most recent 10 failures:
```sql
SELECT 
  publish_time, 
  message_id, 
  data, 
  attributes 
FROM `TODO:PROJECT_ID.pmp_ops.velib_station_info_push_dlq`
WHERE publish_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY publish_time DESC
LIMIT 10;
```

## 6. Replay Plan

### Phase 1: Manual Replay (Now)
1. **Identify**: Query BigQuery to extract the `data` payloads of failed messages.
2. **Export**: Export the result to a JSONL file.
3. **Re-inject**: Use a simple script or `gcloud` to re-publish these messages to the **original topic** (`pmp-velib-station-info`).
   - **Safety Guard**: Always include a `replayed=true` attribute to avoid infinite loops and facilitate tracking.

### Phase 2: Automated Replay Service (Future)
We plan to implement a dedicated **Replay Worker**:
- **Source**: Reads from `pmp-velib-station-info-push-dlq-hold-sub`.
- **Filtering**: Only replays messages matching specific error codes (e.g., bypass 400 Bad Request, retry 500 Internal Error).
- **Idempotency**: Downstream consumers must use `message_id` or a business key (e.g., `station_id` + `last_reported`) to ensure duplicate delivery doesn't corrupt state.
- **Circuit Breaker**: Stops replay if the failure rate on replayed messages exceeds a threshold.

## 7. Monitoring & Alerting Checklist
| Metric | Threshold | Rationale |
| :--- | :--- | :--- |
| `subscription/dead_letter_message_count` | > 0 | Immediate notification that messages are failing processing. |
| `subscription/num_undelivered_messages` | > 500 (Oldest > 1h) | Backlog in the DLQ Hold subscription indicating a systemic failure. |
| `topic/send_request_count` (DLQ Topic) | Spike (> 2x normal) | Massive failure event (e.g., downstream API down). |

## 8. Troubleshooting
- **IAM Permission Denied**:
  - **Symptom**: `dead_letter_message_count` increases but the DLQ Topic shows no incoming messages.
  - **Fix**: Verify the Pub/Sub Service Agent (`service-TODO:PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com`) has `roles/pubsub.publisher` on the DLQ topic.
- **BigQuery Schema Mismatch**:
  - **Symptom**: Messages are "stuck" in the DLQ BigQuery subscription and not appearing in the table.
  - **Fix**: Check `pmp_ops.velib_station_info_push_dlq` table schema. Ensure `data` is still `STRING`.
- **Region Mismatch**:
  - **Symptom**: High latency or egress costs on DLQ delivery.
  - **Fix**: Ensure the BigQuery Dataset `pmp_ops` is in the same region as the Pub/Sub topics/subscriptions (TODO: europe-west9).
