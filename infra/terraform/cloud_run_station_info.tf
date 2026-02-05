# Cloud Run Services for Station Information Pipeline
# Note: Following the existing pattern (docs/03-terraform-iac.md), these Cloud Run
# services should be deployed via `gcloud run deploy` and excluded from Terraform state
# to avoid drift. This file documents the infrastructure but should not be in state.

resource "google_cloud_run_v2_service" "station_info_collector" {
  name     = "pmp-velib-station-info-collector"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.collector_sa.email

    containers {
      image = "gcr.io/${var.project_id}/velib-collector:latest" # Placeholder, built via Cloud Build

      env {
        name  = "TOPIC_ID"
        value = google_pubsub_topic.station_info_topic.name
      }

      env {
        name  = "FEED_URL"
        value = "https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_information.json"
      }

      env {
        name  = "SOURCE"
        value = "velib"
      }

      env {
        name  = "EVENT_TYPE"
        value = "station_information_snapshot"
      }
    }
  }
}

resource "google_cloud_run_v2_service" "station_info_writer" {
  name     = "pmp-velib-station-info-writer"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = google_service_account.station_info_writer_sa.email

    containers {
      image = "gcr.io/${var.project_id}/station-info-writer:latest" # Placeholder, built via Cloud Build

      env {
        name  = "BQ_TABLE"
        value = "${var.project_id}.${google_bigquery_table.velib_station_information.dataset_id}.${google_bigquery_table.velib_station_information.table_id}"
      }
    }
  }
}
