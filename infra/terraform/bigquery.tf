resource "google_bigquery_dataset" "pmp_curated" {
  dataset_id = "pmp_curated"
  location   = "EU"
}

resource "google_bigquery_table" "velib_station_status" {
  dataset_id = google_bigquery_dataset.pmp_curated.dataset_id
  table_id   = "velib_station_status"

  schema = jsonencode([
    { name = "ingest_ts", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "event_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "station_id", type = "STRING", mode = "REQUIRED" },
    { name = "station_code", type = "STRING", mode = "NULLABLE" },
    { name = "is_installed", type = "INT64", mode = "NULLABLE" },
    { name = "is_renting", type = "INT64", mode = "NULLABLE" },
    { name = "is_returning", type = "INT64", mode = "NULLABLE" },
    { name = "last_reported_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "num_bikes_available", type = "INT64", mode = "NULLABLE" },
    { name = "num_docks_available", type = "INT64", mode = "NULLABLE" },
    { name = "mechanical_available", type = "INT64", mode = "NULLABLE" },
    { name = "ebike_available", type = "INT64", mode = "NULLABLE" },
    { name = "raw_station_json", type = "STRING", mode = "NULLABLE" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "ingest_ts"
  }

  clustering = ["station_id"]
}

# Marts Dataset
resource "google_bigquery_dataset" "pmp_marts" {
  dataset_id = "pmp_marts"
  location   = "EU"
}

# Latest State View (Marts Layer)
resource "google_bigquery_table" "velib_latest_state" {
  dataset_id = google_bigquery_dataset.pmp_marts.dataset_id
  table_id   = "velib_latest_state"

  view {
    query = <<-SQL
      SELECT * EXCEPT(rn)
      FROM (
        SELECT
          *,
          ROW_NUMBER() OVER (
            PARTITION BY station_id
            ORDER BY event_ts DESC, ingest_ts DESC
          ) AS rn
        FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
      )
      WHERE rn = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.velib_station_status]
}
