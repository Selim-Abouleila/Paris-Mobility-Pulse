resource "google_project_service" "iam_googleapis_com" {
  project = "19684349165"
  service = "iam.googleapis.com"
}
# terraform import google_project_service.iam_googleapis_com 19684349165/iam.googleapis.com
