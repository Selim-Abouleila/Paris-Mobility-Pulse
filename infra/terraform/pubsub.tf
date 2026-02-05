# Main Events Topic
resource "google_pubsub_topic" "pmp_events" {
  name = "pmp-events"
}

resource "google_pubsub_subscription" "dataflow_sub" {
  name  = "pmp-events-dataflow-sub"
  topic = google_pubsub_topic.pmp_events.name

  ack_deadline_seconds = 60

  expiration_policy {
    ttl = "" # Never expire
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Debug Subscription
resource "google_pubsub_subscription" "pmp_events_sub" {
  name  = "pmp-events-sub"
  topic = google_pubsub_topic.pmp_events.name

  ack_deadline_seconds = 10
  message_retention_duration = "604800s" # 7 days

  expiration_policy {
    ttl = "2678400s" # 31 days
  }
}

# Station Information Topic
resource "google_pubsub_topic" "station_info_topic" {
  name = "pmp-velib-station-info"

  lifecycle {
    prevent_destroy = true
  }
}

# DLQ Topic
resource "google_pubsub_topic" "station_info_dlq_topic" {
  name = "pmp-velib-station-info-push-dlq"

  lifecycle {
    prevent_destroy = true
  }
}

# DLQ Hold Subscription
resource "google_pubsub_subscription" "station_info_dlq_sub" {
  name  = "pmp-velib-station-info-push-dlq-hold-sub"
  topic = google_pubsub_topic.station_info_dlq_topic.name

  message_retention_duration = "604800s" # 7 days (7 * 24 * 60 * 60)

  expiration_policy {
    ttl = "" # Never expire
  }

  lifecycle {
    prevent_destroy = true
  }
}

# DLQ BigQuery Export Subscription
resource "google_pubsub_subscription" "station_info_dlq_bq_sub" {
  name  = "pmp-velib-station-info-push-dlq-to-bq-sub"
  topic = google_pubsub_topic.station_info_dlq_topic.name

  bigquery_config {
    table               = "${var.project_id}.${google_bigquery_table.velib_dlq_raw.dataset_id}.${google_bigquery_table.velib_dlq_raw.table_id}"
    write_metadata      = true
    drop_unknown_fields = false
  }

  expiration_policy {
    ttl = "" # Never expire
  }
}

# Station Information Push Subscription (Source)
resource "google_pubsub_subscription" "station_info_push_sub" {
  name  = "pmp-velib-station-info-to-bq-sub"
  topic = google_pubsub_topic.station_info_topic.name

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.station_info_writer.uri}/pubsub"

    oidc_token {
      service_account_email = google_service_account.pubsub_push_sa.email
      audience              = google_cloud_run_v2_service.station_info_writer.uri
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.station_info_dlq_topic.id
    max_delivery_attempts = 5
  }

  expiration_policy {
    ttl = "" # Never expire
  }

  lifecycle {
    prevent_destroy = true
  }
}

# DLQ Topic IAM: Publisher (Service Agent)
resource "google_pubsub_topic_iam_member" "dlq_publisher_sa" {
  project = var.project_id
  topic   = google_pubsub_topic.station_info_dlq_topic.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Source Subscription IAM: Subscriber (Service Agent)
resource "google_pubsub_subscription_iam_member" "source_subscriber_sa" {
  project      = var.project_id
  subscription = google_pubsub_subscription.station_info_push_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Main Event Subscription (Push to BQ Writer)
resource "google_pubsub_subscription" "pmp_events_to_bq_sub" {
  name  = "pmp-events-to-bq-sub"
  topic = google_pubsub_topic.pmp_events.name

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.pmp_bq_writer.uri}/pubsub"

    oidc_token {
      service_account_email = google_service_account.pubsub_push_sa.email
      audience              = google_cloud_run_v2_service.pmp_bq_writer.uri
    }
  }

  expiration_policy {
    ttl = ""
  }
}
