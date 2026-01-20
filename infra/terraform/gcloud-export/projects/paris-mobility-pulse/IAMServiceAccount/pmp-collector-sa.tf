resource "google_service_account" "pmp_collector_sa" {
  account_id   = "pmp-collector-sa"
  display_name = "PMP Cloud Run Collector"
  project      = "paris-mobility-pulse"
}
# terraform import google_service_account.pmp_collector_sa projects/paris-mobility-pulse/serviceAccounts/pmp-collector-sa@paris-mobility-pulse.iam.gserviceaccount.com
