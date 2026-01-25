output "project_id" {
  value = var.project_id
}

output "dataflow_bucket" {
  value = google_storage_bucket.dataflow_bucket.url
}

output "bigquery_dataset" {
  value = google_bigquery_dataset.pmp_curated.dataset_id
}

output "bigquery_table" {
  value = google_bigquery_table.velib_station_status.table_id
}

output "pubsub_subscription" {
  value = google_pubsub_subscription.dataflow_sub.id
}

output "service_account_email" {
  value = google_service_account.dataflow_sa.email
}

output "marts_dataset" {
  value = google_bigquery_dataset.pmp_marts.dataset_id
}

output "velib_latest_state_view" {
  value = google_bigquery_table.velib_latest_state.table_id
}
