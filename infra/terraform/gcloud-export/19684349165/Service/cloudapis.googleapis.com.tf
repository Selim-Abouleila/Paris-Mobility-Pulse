resource "google_project_service" "cloudapis_googleapis_com" {
  project = "19684349165"
  service = "cloudapis.googleapis.com"
}
# terraform import google_project_service.cloudapis_googleapis_com 19684349165/cloudapis.googleapis.com
