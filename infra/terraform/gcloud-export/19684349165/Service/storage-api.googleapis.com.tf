resource "google_project_service" "storage_api_googleapis_com" {
  project = "19684349165"
  service = "storage-api.googleapis.com"
}
# terraform import google_project_service.storage_api_googleapis_com 19684349165/storage-api.googleapis.com
