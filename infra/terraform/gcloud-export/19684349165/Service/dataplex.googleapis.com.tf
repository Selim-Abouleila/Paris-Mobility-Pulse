resource "google_project_service" "dataplex_googleapis_com" {
  project = "19684349165"
  service = "dataplex.googleapis.com"
}
# terraform import google_project_service.dataplex_googleapis_com 19684349165/dataplex.googleapis.com
