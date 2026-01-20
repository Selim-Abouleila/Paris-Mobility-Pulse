resource "google_project_service" "datastore_googleapis_com" {
  project = "19684349165"
  service = "datastore.googleapis.com"
}
# terraform import google_project_service.datastore_googleapis_com 19684349165/datastore.googleapis.com
