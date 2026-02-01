#!/bin/bash
set -e

# Import DLQ Topic
terraform import google_pubsub_topic.station_info_dlq_topic projects/paris-mobility-pulse/topics/pmp-velib-station-info-push-dlq

# Import DLQ Hold Subscription
terraform import google_pubsub_subscription.station_info_dlq_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-push-dlq-hold-sub

# Import Source Subscription (if untracked)
terraform import google_pubsub_subscription.station_info_push_sub projects/paris-mobility-pulse/subscriptions/pmp-velib-station-info-to-bq-sub

echo "Import complete. Run 'terraform plan' to verify."
