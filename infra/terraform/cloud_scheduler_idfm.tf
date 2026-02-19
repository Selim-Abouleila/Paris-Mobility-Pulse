# IDFM Polling Job (Cloud Scheduler)
resource "google_cloud_scheduler_job" "idfm_poll" {
  name             = "idfm-poll-every-10min"
  description      = "Triggers IDFM collector every 10 minutes"
  schedule         = "*/10 * * * *" # Every 10 min
  time_zone        = "Europe/Paris"
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = google_cloud_run_v2_service.pmp_idfm_collector.uri

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
}
