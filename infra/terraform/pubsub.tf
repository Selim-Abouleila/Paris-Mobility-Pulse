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
