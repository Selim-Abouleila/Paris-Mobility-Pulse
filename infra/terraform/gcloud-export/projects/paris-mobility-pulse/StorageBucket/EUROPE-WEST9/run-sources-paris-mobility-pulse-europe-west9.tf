resource "google_storage_bucket" "run_sources_paris_mobility_pulse_europe_west9" {
  cors {
    method = ["GET"]
    origin = ["https://*.cloud.google.com", "https://*.corp.google.com", "https://*.corp.google.com:*", "https://*.cloud.google", "https://*.byoid.goog"]
  }

  force_destroy = false

  labels = {
    managed-by-cnrm = "true"
  }

  location                 = "EUROPE-WEST9"
  name                     = "run-sources-paris-mobility-pulse-europe-west9"
  
  public_access_prevention = "inherited"

  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
}
# terraform import google_storage_bucket.run_sources_paris_mobility_pulse_europe_west9 run-sources-paris-mobility-pulse-europe-west9
