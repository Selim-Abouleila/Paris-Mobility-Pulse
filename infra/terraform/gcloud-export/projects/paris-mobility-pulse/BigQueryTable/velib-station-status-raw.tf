resource "google_bigquery_table" "velib_station_status_raw" {
  clustering = ["source", "event_type", "key"]
  dataset_id = "pmp_raw"

  labels = {
    managed-by-cnrm = "true"
  }

  
  schema   = "[{\"mode\":\"REQUIRED\",\"name\":\"ingest_ts\",\"type\":\"TIMESTAMP\"},{\"mode\":\"NULLABLE\",\"name\":\"event_ts\",\"type\":\"TIMESTAMP\"},{\"mode\":\"REQUIRED\",\"name\":\"source\",\"type\":\"STRING\"},{\"mode\":\"REQUIRED\",\"name\":\"event_type\",\"type\":\"STRING\"},{\"mode\":\"REQUIRED\",\"name\":\"key\",\"type\":\"STRING\"},{\"mode\":\"REQUIRED\",\"name\":\"payload\",\"type\":\"JSON\"}]"
  table_id = "velib_station_status_raw"

  time_partitioning {
    field = "ingest_ts"
    type  = "DAY"
  }
}
# terraform import google_bigquery_table.velib_station_status_raw projects/paris-mobility-pulse/datasets/pmp_raw/tables/velib_station_status_raw
