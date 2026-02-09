# Placeholder for future secrets management
# Doc 10x - Security Implementation Plan

resource "google_secret_manager_secret" "api_key_placeholder" {
  secret_id = "pmp-api-key-placeholder"

  replication {
    auto {}
  }
}

# Example of granting access to a service account (commented out until needed)
# resource "google_secret_manager_secret_iam_member" "collector_access" {
#   secret_id = google_secret_manager_secret.api_key_placeholder.id
#   role      = "roles/secretmanager.secretAccessor"
#   member    = "serviceAccount:${google_service_account.collector_sa.email}"
# }
