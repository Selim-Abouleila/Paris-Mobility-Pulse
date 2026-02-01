# 09 - Reliability: DLQ + Replay

> [!NOTE]
> **Status**
> ✅ **Implemented today**: DLQ topic, `dead_letter_policy`, DLQ hold subscription, BigQuery export subscription, and DLQ table created.
> ⏳ **Planned next**: Replay worker automation, Dataflow DLQ integration, and automated monitoring dashboards.

## 1. Goal & Dead Lettering Semantics
In a production streaming pipeline, failures are inevitable. The Dead Letter Queue (DLQ) pattern prevents "head-of-line blocking" where a single poisonous message prevents the processing of subsequent messages.

### How it Works
1. **Pub/Sub Retries**: When a push endpoint (Cloud Run) returns a non-success code (e.g., 500), Pub/Sub retries delivery based on the retry policy.
2. **Forwarding to DLQ**: After approximately `maxDeliveryAttempts` (defaulting to 5 in our setup), Pub/Sub forwards the message to the **DLQ Topic**.
3. **Message Wrapping**: When forwarding, Pub/Sub wraps the original message and adds metadata attributes (like `CloudPubSubDeadLetterSourceSubscription`) identifying the origin.
4. **IAM Requirements**: For this handshake to work, the **Pub/Sub Service Agent** requires:
   - `roles/pubsub.publisher` on the **DLQ Topic**.
   - `roles/pubsub.subscriber` on the **Source Subscription**.

## 2. Architecture
Failed messages are diverted by Pub/Sub and exported to BigQuery for long-term auditability and analysis.

```text
[ pmp-velib-station-info (Original Topic) ] 
       |
       v
[ pmp-velib-station-info-to-bq-sub (Push Sub) ] -- (Max 5 attempts) --> [ Cloud Run Writer ]
       |                                                                      |
       | (On Failure / 5xx)                                                   | (HTTP 500)
       v
[ pmp-velib-station-info-push-dlq (DLQ Topic) ] 
       |
       +-----> [ pmp-velib-station-info-push-dlq-hold-sub ] (7-day retention for manual replay)
       |
       +-----> [ pmp-velib-station-info-push-dlq-to-bq-sub ] (BQ Export)
                      |
                      v
               [ pmp_ops (Dataset) ] -> [ velib_station_info_push_dlq (Table) ]
```

## 3. Data Model
### BigQuery Table: `paris-mobility-pulse.pmp_ops.velib_station_info_push_dlq`
| Column | Type | Description |
| :--- | :--- | :--- |
| `subscription_name` | STRING | The ID of the subscription that moved the message to DLQ. |
| `message_id` | STRING | Unique Pub/Sub message ID. |
| `publish_time` | TIMESTAMP | Original publish timestamp (Requires `write_metadata=true`). |
| `data` | STRING | Raw message payload. |
| `attributes` | STRING | JSON-serialized metadata. |

> [!IMPORTANT]
> **Why `attributes` is STRING?**
> We store attributes as a serialized JSON STRING rather than the `JSON` type for maximum compatibility during ingestion. BigQuery's native JSON functions (e.g., `JSON_QUERY`, `JSON_VALUE`) can still be used on these strings for analysis.

> [!WARNING]
> If `write_metadata` is not enabled on the BigQuery export subscription, `publish_time` and `attributes` will be **NULL**. This also breaks time-based partitioning.

**Partitioning**: The table is partitioned by `publish_time`. If metadata is disabled, all rows will fall into the `NULL` partition.

## 4. Verification Tests

### Test A: Sanity Check (Direct Publish)
Verify that messages published to the DLQ topic arrive in BigQuery.
```bash
gcloud pubsub topics publish pmp-velib-station-info-push-dlq \
  --message='{"test": "sanity_check", "status": "direct_to_dlq"}' \
  --attribute="test_type=manual"
```
Wait ~30 seconds and check BQ:
```bash
bq query --use_legacy_sql=false \
'SELECT * FROM `paris-mobility-pulse.pmp_ops.velib_station_info_push_dlq` WHERE data LIKE "%sanity_check%"'
```

### Test B: End-to-End DLQ Forwarding
Verify that a failing Cloud Run handler correctly triggers the DLQ flow.
1. **Implement Feature Flag**: In the Cloud Run writer code, add a check:
   ```python
   if attributes.get("dlq_test") == "true":
       return "Simulated Failure", 500
   ```
2. **Publish to Original Topic**:
   ```bash
   gcloud pubsub topics publish pmp-velib-station-info \
     --message='{"test": "e2e_dlq_test"}' \
     --attribute="dlq_test=true"
   ```
3. **Confirm Delivery**: After Pub/Sub exhausts retries (check `maxDeliveryAttempts`), the message should appear in the DLQ BigQuery table with the original payload.

## 5. Terraform Infrastructure
The following resources should be managed in Terraform with `lifecycle { prevent_destroy = true }` where applicable.

### Resources
- `google_pubsub_topic.pmp_velib_station_info_push_dlq`
- `google_pubsub_subscription.pmp_velib_station_info_push_dlq_hold_sub`
- `google_pubsub_subscription.pmp_velib_station_info_to_bq_sub` (with `dead_letter_policy`)
- `google_bigquery_dataset.pmp_ops`
- `google_bigquery_table.velib_station_info_push_dlq`
- `google_pubsub_subscription.pmp_velib_station_info_push_dlq_to_bq_sub` (with `bigquery_config.write_metadata = true`)

### IAM Bindings
The Pub/Sub service agent needs the following:
- **Publisher** on `projects/paris-mobility-pulse/topics/pmp-velib-station-info-push-dlq`
- **Subscriber** on `projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-to-bq-sub`
- **BigQuery Data Editor** on the `pmp_ops` dataset.

### Import Commands
```bash
# Topics
terraform import google_pubsub_topic.dlq_topic projects/paris-mobility-pulse/topics/pmp-velib-station-info-push-dlq

# Subscriptions
terraform import google_pubsub_subscription.dlq_hold_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-push-dlq-hold-sub
terraform import google_pubsub_subscription.dlq_bq_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-push-dlq-to-bq-sub

# BigQuery
terraform import google_bigquery_dataset.pmp_ops projects/paris-mobility-pulse/datasets/pmp_ops
terraform import google_bigquery_table.dlq_table projects/paris-mobility-pulse/datasets/pmp_ops/tables/velib_station_info_push_dlq
```

## 6. Monitoring
Use these official Cloud Monitoring metrics to track DLQ health:

| Metric Name | Threshold | Rationale |
| :--- | :--- | :--- |
| `subscription/dead_letter_message_count` | `> 0` | Indicates messages are actively failing and being diverted. |
| `subscription/num_undelivered_messages` | `> 100` | Large backlog on the DLQ Hold sub indicates high failure volume. |
| `subscription/oldest_unacked_message_age` | `> 3600s` | Messages are "stuck" and not being processed/exported to BQ. |

## 7. Troubleshooting
- **IAM Failures**: If `dead_letter_message_count` is increasing but the DLQ topic is empty, ensure the Pub/Sub service agent has Publisher permissions on the DLQ topic.
- **Why `publish_time` is NULL?**: Check if `write_metadata` is set to `true` on the BQ export subscription. If it was enabled after messages were already in the queue, only new messages will have metadata.
- **Location Mismatch**: Ensure BQ dataset `pmp_ops` is in `europe-west9` to match the Pub/Sub regional endpoints and minimize egress costs/latency.
- **Schema Mismatch**: BigQuery will drop messages if the schema doesn't match. Ensure columns like `data` are `STRING` to capture any payload (even invalid JSON).
