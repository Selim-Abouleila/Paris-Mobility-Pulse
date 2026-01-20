resource "google_project_service" "cloudbuild_googleapis_com" {
  project = "19684349165"
  service = "cloudbuild.googleapis.com"
}
# terraform import google_project_service.cloudbuild_googleapis_com 19684349165/cloudbuild.googleapis.com
