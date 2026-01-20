resource "google_project_service" "cloudtrace_googleapis_com" {
  project = "19684349165"
  service = "cloudtrace.googleapis.com"
}
# terraform import google_project_service.cloudtrace_googleapis_com 19684349165/cloudtrace.googleapis.com
