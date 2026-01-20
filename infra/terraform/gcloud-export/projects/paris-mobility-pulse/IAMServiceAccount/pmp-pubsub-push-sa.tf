resource "google_service_account" "pmp_pubsub_push_sa" {
  account_id   = "pmp-pubsub-push-sa"
  display_name = "PMP PubSub Push Invoker"
  project      = "paris-mobility-pulse"
}
# terraform import google_service_account.pmp_pubsub_push_sa projects/paris-mobility-pulse/serviceAccounts/pmp-pubsub-push-sa@paris-mobility-pulse.iam.gserviceaccount.com
