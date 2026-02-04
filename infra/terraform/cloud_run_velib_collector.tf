resource "google_cloud_run_v2_service" "pmp_velib_collector" {
  name     = "pmp-velib-collector"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.collector_sa.email

    containers {
      image = "gcr.io/${var.project_id}/velib-collector:latest"

      env {
        name  = "TOPIC_ID"
        value = "pmp-events"
      }
      env {
        name  = "FEED_URL"
        value = "https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_status.json"
      }
      env {
        name  = "SOURCE"
        value = "velib"
      }
      env {
        name  = "EVENT_TYPE"
        value = "station_status_snapshot"
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    }
  }
}
