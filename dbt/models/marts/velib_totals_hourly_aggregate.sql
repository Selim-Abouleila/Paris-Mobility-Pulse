
WITH snapshots AS (
  SELECT
    ingest_ts,
    TIMESTAMP_TRUNC(COALESCE(event_ts, ingest_ts), HOUR, "Europe/Paris") as hour_ts_paris,
    COUNT(DISTINCT station_id) as stations_reporting,
    SUM(num_bikes_available) as total_bikes,
    SUM(num_docks_available) as total_docks,
    COUNTIF(num_bikes_available = 0) as empty_stations
  FROM {{ source('pmp_curated', 'velib_station_status') }}
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
