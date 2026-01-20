resource "google_project_service" "containerregistry_googleapis_com" {
  project = "19684349165"
  service = "containerregistry.googleapis.com"
}
# terraform import google_project_service.containerregistry_googleapis_com 19684349165/containerregistry.googleapis.com
