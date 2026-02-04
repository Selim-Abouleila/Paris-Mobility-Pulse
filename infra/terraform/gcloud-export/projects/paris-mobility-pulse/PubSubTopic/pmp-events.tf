resource "google_pubsub_topic" "pmp_events" {
  labels = {
    managed-by-cnrm = "true"
  }

  name = "pmp-events"
}
# terraform import google_pubsub_topic.pmp_events projects/paris-mobility-pulse/topics/pmp-events
