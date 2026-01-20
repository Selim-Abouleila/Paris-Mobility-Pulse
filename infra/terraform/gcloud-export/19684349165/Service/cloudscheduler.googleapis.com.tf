resource "google_project_service" "cloudscheduler_googleapis_com" {
  project = "19684349165"
  service = "cloudscheduler.googleapis.com"
}
# terraform import google_project_service.cloudscheduler_googleapis_com 19684349165/cloudscheduler.googleapis.com
