resource "google_project_service" "logging_googleapis_com" {
  project = "19684349165"
  service = "logging.googleapis.com"
}
# terraform import google_project_service.logging_googleapis_com 19684349165/logging.googleapis.com
