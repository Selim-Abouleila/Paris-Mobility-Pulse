# Cloud Scheduler Job for Station Information Collection

resource "google_cloud_scheduler_job" "station_info_daily" {
  name             = "pmp-velib-station-info-daily"
  description      = "Daily collection of Vélib station information (static data)"
  schedule         = "10 3 * * *"
  time_zone        = "Europe/Paris"
  region           = var.scheduler_location
  attempt_deadline = "320s"

  http_target {
    http_method = "GET"
    uri         = "${google_cloud_run_v2_service.station_info_collector.uri}/collect"

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
      audience              = google_cloud_run_v2_service.station_info_collector.uri
    }
  }

  retry_config {
    retry_count = 3
  }
}
