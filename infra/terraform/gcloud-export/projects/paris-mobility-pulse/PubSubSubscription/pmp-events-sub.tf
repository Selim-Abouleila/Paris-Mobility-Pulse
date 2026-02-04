resource "google_pubsub_subscription" "pmp_events_sub" {
  ack_deadline_seconds = 10

  expiration_policy {
    ttl = "2678400s"
  }

  labels = {
    managed-by-cnrm = "true"
  }

  message_retention_duration = "604800s"
  name                       = "pmp-events-sub"
  
  topic                      = "projects/paris-mobility-pulse/topics/pmp-events"
}
# terraform import google_pubsub_subscription.pmp_events_sub projects/paris-mobility-pulse/subscriptions/pmp-events-sub
