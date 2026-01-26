# We reference the existing topic
data "google_pubsub_topic" "pmp_events" {
  name = "pmp-events"
}

resource "google_pubsub_subscription" "dataflow_sub" {
  name  = "pmp-events-dataflow-sub"
  topic = data.google_pubsub_topic.pmp_events.name

  ack_deadline_seconds = 60

  expiration_policy {
    ttl = "" # Never expire
  }
}

# Station Information Topic
resource "google_pubsub_topic" "station_info_topic" {
  name = "pmp-velib-station-info"
}

# Station Information Push Subscription
resource "google_pubsub_subscription" "station_info_push_sub" {
  name  = "pmp-velib-station-info-to-bq-sub"
  topic = google_pubsub_topic.station_info_topic.name

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.station_info_writer.uri}/pubsub"

    oidc_token {
      service_account_email = data.google_service_account.pubsub_push_sa.email
      audience              = google_cloud_run_v2_service.station_info_writer.uri
    }
  }

  expiration_policy {
    ttl = "" # Never expire
  }
}
