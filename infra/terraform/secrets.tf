# Placeholder for future secrets management
# Doc 10x - Security Implementation Plan

resource "google_secret_manager_secret" "api_key_placeholder" {
  secret_id = "pmp-api-key-placeholder"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

# -----------------------------------------------------------------------------
# IDFM Transit Disruptions API Key
# -----------------------------------------------------------------------------
resource "google_secret_manager_secret" "idfm_api_key" {
  secret_id = "pmp-idfm-api-key"
  
  replication {
    auto {}
  }
}



