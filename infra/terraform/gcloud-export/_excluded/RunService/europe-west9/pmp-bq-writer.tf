resource "google_cloud_run_v2_service" "pmp_bq_writer" {
  client         = "gcloud"
  client_version = "551.0.0"
  ingress        = "INGRESS_TRAFFIC_ALL"

  labels = {
    managed-by-cnrm = "true"
  }

  launch_stage = "GA"
  location     = "europe-west9"
  name         = "pmp-bq-writer"

  template {
    containers {
      env {
        name  = "BQ_DATASET"
        value = "pmp_raw"
      }

      env {
        name  = "BQ_TABLE"
        value = "velib_station_status_raw"
      }

      image = "europe-west9-docker.pkg.dev/paris-mobility-pulse/cloud-run-source-deploy/pmp-bq-writer@sha256:81020af9f17318f4e5633501d4dfd1126851d9f1cf7172bbf1adb95b9c33cb4e"

      ports {
        container_port = 8080
        name           = "http1"
      }

      resources {
        cpu_idle = true

        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }

        startup_cpu_boost = true
      }

      startup_probe {
        failure_threshold     = 1
        initial_delay_seconds = 0
        period_seconds        = 240

        tcp_socket {
          port = 8080
        }

        timeout_seconds = 240
      }
    }

    max_instance_request_concurrency = 80

    scaling {
      max_instance_count = 3
    }

    service_account = "pmp-bq-writer-sa@paris-mobility-pulse.iam.gserviceaccount.com"
    timeout         = "300s"
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
}
# terraform import google_cloud_run_v2_service.pmp_bq_writer projects/paris-mobility-pulse/locations/europe-west9/services/pmp-bq-writer
