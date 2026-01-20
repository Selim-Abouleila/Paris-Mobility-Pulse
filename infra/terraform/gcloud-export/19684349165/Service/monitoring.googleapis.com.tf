resource "google_project_service" "monitoring_googleapis_com" {
  project = "19684349165"
  service = "monitoring.googleapis.com"
}
# terraform import google_project_service.monitoring_googleapis_com 19684349165/monitoring.googleapis.com
