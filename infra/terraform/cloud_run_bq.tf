resource "google_cloud_run_v2_service" "pmp_bq_writer" {
  name     = "pmp-bq-writer"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = google_service_account.pubsub_push_sa.email

    containers {
      image = "gcr.io/${var.project_id}/bq-writer:latest"

      env {
        name  = "BQ_DATASET"
        value = google_bigquery_dataset.pmp_raw.dataset_id
      }
      env {
        name  = "BQ_TABLE"
        value = "velib_station_status_raw"
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
