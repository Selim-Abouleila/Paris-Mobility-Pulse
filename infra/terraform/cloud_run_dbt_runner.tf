# dbt Runner — Cloud Run Job + Cloud Scheduler
# Runs dbt incremental models on a schedule

resource "google_cloud_run_v2_job" "dbt_runner" {
  name                = "pmp-dbt-runner"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.dbt_runner_sa.email
      timeout         = "600s" # 10 min max

      containers {
        image = "gcr.io/${var.project_id}/dbt-runner:latest"

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "DBT_LOCATION"
          value = "EU"
        }
      }
    }
  }
}

# Schedule: run dbt every hour
resource "google_cloud_scheduler_job" "dbt_run_hourly" {
  name             = "dbt-run-every-hour"
  description      = "Triggers dbt incremental run every hour"
  schedule         = "0 * * * *" # Top of every hour
  time_zone        = "Europe/Paris"
  attempt_deadline = "320s"
  region           = var.scheduler_location

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/pmp-dbt-runner:run"

    oauth_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
}
