resource "google_storage_bucket" "dataflow_bucket" {
  name          = "pmp-dataflow-${var.project_id}"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age            = 7
      matches_prefix = ["temp/", "staging/"]
    }
    action {
      type = "Delete"
    }
  }
}
