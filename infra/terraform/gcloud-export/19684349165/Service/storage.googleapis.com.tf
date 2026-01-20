resource "google_project_service" "storage_googleapis_com" {
  project = "19684349165"
  service = "storage.googleapis.com"
}
# terraform import google_project_service.storage_googleapis_com 19684349165/storage.googleapis.com
