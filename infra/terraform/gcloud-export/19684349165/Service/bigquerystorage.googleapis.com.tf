resource "google_project_service" "bigquerystorage_googleapis_com" {
  project = "19684349165"
  service = "bigquerystorage.googleapis.com"
}
# terraform import google_project_service.bigquerystorage_googleapis_com 19684349165/bigquerystorage.googleapis.com
