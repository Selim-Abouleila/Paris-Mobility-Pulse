# IDFM Collector Service (Cloud Run)
resource "google_cloud_run_v2_service" "pmp_idfm_collector" {
  name     = "pmp-idfm-collector"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.idfm_collector_sa.email

    containers {
      # Placeholder image until the real one is built
      image = "us-docker.pkg.dev/cloudrun/container/hello" 

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name = "IDFM_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.idfm_api_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image, # Ignore image changes (managed by CI/CD)
      client,
      client_version
    ]
  }
}
