
resource "google_bigquery_table" "idfm_disruptions_raw" {
  dataset_id = google_bigquery_dataset.pmp_raw.dataset_id
  table_id   = "idfm_disruptions_raw"

  schema = jsonencode([
    { name = "ingest_ts", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "event_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "source", type = "STRING", mode = "REQUIRED" },
    { name = "event_type", type = "STRING", mode = "REQUIRED" },
    { name = "key", type = "STRING", mode = "REQUIRED" },
    { name = "payload", type = "JSON", mode = "REQUIRED" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "ingest_ts"
  }

  clustering = ["source", "event_type"]

  lifecycle {
    ignore_changes = all
  }
}
