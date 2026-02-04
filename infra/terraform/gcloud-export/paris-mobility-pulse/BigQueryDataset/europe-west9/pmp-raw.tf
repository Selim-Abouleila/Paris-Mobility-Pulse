resource "google_bigquery_dataset" "pmp_raw" {
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role          = "OWNER"
    user_by_email = "selimabouleila@gmail.com"
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }

  dataset_id                 = "pmp_raw"
  delete_contents_on_destroy = false

  labels = {
    managed-by-cnrm = "true"
  }

  location              = "europe-west9"
  max_time_travel_hours = "168"
}
# terraform import google_bigquery_dataset.pmp_raw projects/paris-mobility-pulse/datasets/pmp_raw
