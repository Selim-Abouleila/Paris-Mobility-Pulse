resource "google_project_service" "iamcredentials_googleapis_com" {
  project = "19684349165"
  service = "iamcredentials.googleapis.com"
}
# terraform import google_project_service.iamcredentials_googleapis_com 19684349165/iamcredentials.googleapis.com
