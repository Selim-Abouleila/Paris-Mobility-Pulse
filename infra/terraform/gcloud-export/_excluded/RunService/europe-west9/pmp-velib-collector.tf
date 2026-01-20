resource "google_cloud_run_v2_service" "pmp_velib_collector" {
  client         = "gcloud"
  client_version = "551.0.0"
  ingress        = "INGRESS_TRAFFIC_ALL"

  labels = {
    managed-by-cnrm = "true"
  }

  launch_stage = "GA"
  location     = "europe-west9"
  name         = "pmp-velib-collector"
  project      = "paris-mobility-pulse"

  template {
    containers {
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

      image = "europe-west9-docker.pkg.dev/paris-mobility-pulse/cloud-run-source-deploy/pmp-velib-collector@sha256:476f413d4717ad0d153deb34080575ddc42628658afd6a9339f0a5d6a13b621d"

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
    service_account                  = "pmp-collector-sa@paris-mobility-pulse.iam.gserviceaccount.com"
    timeout                          = "300s"
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
}
# terraform import google_cloud_run_v2_service.pmp_velib_collector projects/paris-mobility-pulse/locations/europe-west9/services/pmp-velib-collector
