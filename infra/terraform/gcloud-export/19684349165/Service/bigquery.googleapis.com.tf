resource "google_project_service" "bigquery_googleapis_com" {
  project = "19684349165"
  service = "bigquery.googleapis.com"
}
# terraform import google_project_service.bigquery_googleapis_com 19684349165/bigquery.googleapis.com
