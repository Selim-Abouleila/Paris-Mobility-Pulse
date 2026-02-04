resource "google_service_account" "pmp_bq_writer_sa" {
  account_id   = "pmp-bq-writer-sa"
  display_name = "PMP BigQuery Writer"
}
# terraform import google_service_account.pmp_bq_writer_sa projects/paris-mobility-pulse/serviceAccounts/pmp-bq-writer-sa@paris-mobility-pulse.iam.gserviceaccount.com
