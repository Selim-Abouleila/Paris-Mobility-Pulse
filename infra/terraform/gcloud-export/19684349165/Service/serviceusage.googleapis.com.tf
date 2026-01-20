resource "google_project_service" "serviceusage_googleapis_com" {
  project = "19684349165"
  service = "serviceusage.googleapis.com"
}
# terraform import google_project_service.serviceusage_googleapis_com 19684349165/serviceusage.googleapis.com
