resource "google_service_account" "pmp_scheduler_sa" {
  account_id   = "pmp-scheduler-sa"
  display_name = "PMP Scheduler Invoker"
  project      = "paris-mobility-pulse"
}
# terraform import google_service_account.pmp_scheduler_sa projects/paris-mobility-pulse/serviceAccounts/pmp-scheduler-sa@paris-mobility-pulse.iam.gserviceaccount.com
