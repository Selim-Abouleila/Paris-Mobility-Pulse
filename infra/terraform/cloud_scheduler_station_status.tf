resource "google_cloud_scheduler_job" "velib_poll_every_minute" {
  name        = "pmp-velib-poll-every-minute"
  description = "Triggers the Velib station status collector every minute"
  schedule    = "* * * * *"
  time_zone   = "Europe/Paris"
  region      = var.scheduler_location

  http_target {
    http_method = "GET"
    uri         = "${google_cloud_run_v2_service.pmp_velib_collector.uri}/collect"

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
      audience              = google_cloud_run_v2_service.pmp_velib_collector.uri
    }
  }

  retry_config {
    retry_count = 1
  }
}
