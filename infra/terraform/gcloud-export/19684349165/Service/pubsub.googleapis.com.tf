resource "google_project_service" "pubsub_googleapis_com" {
  project = "19684349165"
  service = "pubsub.googleapis.com"
}
# terraform import google_project_service.pubsub_googleapis_com 19684349165/pubsub.googleapis.com
