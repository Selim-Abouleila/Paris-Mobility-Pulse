resource "google_project_service" "run_googleapis_com" {
  project = "19684349165"
  service = "run.googleapis.com"
}
# terraform import google_project_service.run_googleapis_com 19684349165/run.googleapis.com
