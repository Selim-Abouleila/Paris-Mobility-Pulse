resource "google_pubsub_subscription" "pmp_events_to_bq_sub" {
  ack_deadline_seconds = 10

  expiration_policy {
    ttl = "2678400s"
  }

  labels = {
    managed-by-cnrm = "true"
  }

  message_retention_duration = "604800s"
  name                       = "pmp-events-to-bq-sub"
  

  push_config {
    oidc_token {
      audience              = "https://pmp-bq-writer-2cyaolkqiq-od.a.run.app"
      service_account_email = "pmp-pubsub-push-sa@paris-mobility-pulse.iam.gserviceaccount.com"
    }

    push_endpoint = "https://pmp-bq-writer-2cyaolkqiq-od.a.run.app/pubsub"
  }

  topic = "projects/paris-mobility-pulse/topics/pmp-events"
}
# terraform import google_pubsub_subscription.pmp_events_to_bq_sub projects/paris-mobility-pulse/subscriptions/pmp-events-to-bq-sub
