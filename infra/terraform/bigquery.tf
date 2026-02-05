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

# Ops Dataset (DLQ)
resource "google_bigquery_dataset" "pmp_ops" {
  dataset_id = "pmp_ops"
  location   = var.region
}

# Raw Dataset (Landing Zone)
resource "google_bigquery_dataset" "pmp_raw" {
  dataset_id = "pmp_raw"
  location   = var.region
}

# DLQ Table (Pub/Sub Station Info)
resource "google_bigquery_table" "velib_dlq_raw" {
  dataset_id = google_bigquery_dataset.pmp_ops.dataset_id
  table_id   = "velib_station_info_push_dlq"

  schema = file("dlq_table_schema.json")

  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }
}

# DLQ Table (Dataflow Curated)
resource "google_bigquery_table" "velib_station_status_curated_dlq" {
  dataset_id = google_bigquery_dataset.pmp_ops.dataset_id
  table_id   = "velib_station_status_curated_dlq"

  schema = jsonencode([
    { name = "dlq_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "stage", type = "STRING", mode = "NULLABLE" },
    { name = "error_type", type = "STRING", mode = "NULLABLE" },
    { name = "error_message", type = "STRING", mode = "NULLABLE" },
    { name = "raw", type = "STRING", mode = "NULLABLE" },
    { name = "event_meta", type = "STRING", mode = "NULLABLE" },
    { name = "row_json", type = "STRING", mode = "NULLABLE" },
    { name = "bq_errors", type = "STRING", mode = "NULLABLE" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "dlq_ts"
  }

  lifecycle {
    prevent_destroy = true
  }

  deletion_protection = true
}


# IAM for Pub/Sub Service Agent to write to DLQ Dataset
resource "google_bigquery_dataset_iam_member" "pubsub_sa_dlq_editor" {
  dataset_id = google_bigquery_dataset.pmp_ops.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_bigquery_dataset_iam_member" "pubsub_sa_dlq_viewer" {
  dataset_id = google_bigquery_dataset.pmp_ops.dataset_id
  role       = "roles/bigquery.metadataViewer"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Latest State View (Marts Layer)
resource "google_bigquery_table" "velib_latest_state" {
  dataset_id = google_bigquery_dataset.pmp_marts.dataset_id
  table_id   = "velib_latest_state"

  view {
    query          = <<-SQL
      SELECT * EXCEPT(rn)
      FROM (
        SELECT
          *,
          ROW_NUMBER() OVER (
            PARTITION BY station_id
            ORDER BY event_ts DESC, ingest_ts DESC
          ) AS rn
        FROM `${var.project_id}.pmp_curated.velib_station_status`
      )
      WHERE rn = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.velib_station_status]
}

# Station Information Table (Curated)
resource "google_bigquery_table" "velib_station_information" {
  dataset_id = google_bigquery_dataset.pmp_curated.dataset_id
  table_id   = "velib_station_information"

  schema = jsonencode([
    { name = "ingest_ts", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "event_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "station_id", type = "STRING", mode = "REQUIRED" },
    { name = "station_code", type = "STRING", mode = "NULLABLE" },
    { name = "name", type = "STRING", mode = "NULLABLE" },
    { name = "lat", type = "FLOAT64", mode = "NULLABLE" },
    { name = "lon", type = "FLOAT64", mode = "NULLABLE" },
    { name = "capacity", type = "INT64", mode = "NULLABLE" },
    { name = "address", type = "STRING", mode = "NULLABLE" },
    { name = "post_code", type = "STRING", mode = "NULLABLE" },
    { name = "raw_station_json", type = "STRING", mode = "NULLABLE" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "ingest_ts"
  }

  clustering = ["station_id"]
}

# Hourly Aggregates Base View (Virtual Materialized View Logic)
resource "google_bigquery_table" "velib_totals_hourly_mv" {
  dataset_id = google_bigquery_dataset.pmp_marts.dataset_id
  table_id   = "velib_totals_hourly_aggregate"

  view {
    query          = <<-SQL
      WITH snapshots AS (
        SELECT
          ingest_ts,
          TIMESTAMP_TRUNC(COALESCE(event_ts, ingest_ts), HOUR, "Europe/Paris") as hour_ts_paris,
          COUNT(DISTINCT station_id) as stations_reporting,
          SUM(num_bikes_available) as total_bikes,
          SUM(num_docks_available) as total_docks,
          COUNTIF(num_bikes_available = 0) as empty_stations
        FROM `${var.project_id}.pmp_curated.velib_station_status`
        GROUP BY 1, 2
      )
      SELECT
        hour_ts_paris,
        AVG(total_bikes) as avg_total_bikes_available,
        MAX(total_bikes) as peak_total_bikes_available,
        MIN(total_bikes) as min_total_bikes_available,
        AVG(total_docks) as avg_total_docks_available,
        AVG(stations_reporting) as avg_stations_reporting,
        AVG(empty_stations) as avg_empty_stations,
        MAX(empty_stations) as peak_empty_stations,
        COUNT(*) as snapshot_samples
      FROM snapshots
      GROUP BY 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.velib_station_status]
}

# Hourly Dashboard View (Looker Wrapper)
resource "google_bigquery_table" "velib_totals_hourly" {
  dataset_id = google_bigquery_dataset.pmp_marts.dataset_id
  table_id   = "velib_totals_hourly"

  view {
    query          = <<-SQL
      SELECT
        base.*,
        DATETIME(base.hour_ts_paris, "Europe/Paris") as hour_paris,
        info.total_stations_known,
        SAFE_DIVIDE(base.avg_stations_reporting, info.total_stations_known) as avg_coverage_ratio
      FROM `${var.project_id}.pmp_marts.velib_totals_hourly_aggregate` base
      CROSS JOIN (
        SELECT COUNT(DISTINCT station_id) as total_stations_known
        FROM `${var.project_id}.pmp_curated.velib_station_information`
      ) info
    SQL
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.velib_totals_hourly_mv,
    google_bigquery_table.velib_station_information
  ]
}
