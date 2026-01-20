resource "google_project_service" "dataform_googleapis_com" {
  project = "19684349165"
  service = "dataform.googleapis.com"
}
# terraform import google_project_service.dataform_googleapis_com 19684349165/dataform.googleapis.com
