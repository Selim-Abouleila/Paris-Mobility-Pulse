
SELECT
  base.hour_ts_paris AS hour_ts,
  DATETIME(base.hour_ts_paris, "Europe/Paris") as hour_paris,
  DATE(DATETIME(base.hour_ts_paris, "Europe/Paris")) AS date_paris,
  EXTRACT(HOUR FROM DATETIME(base.hour_ts_paris, "Europe/Paris")) AS hour_of_day_paris,
  base.avg_total_bikes_available,
  base.peak_total_bikes_available,
  base.min_total_bikes_available,
  base.avg_total_docks_available,
  base.avg_stations_reporting,
  base.avg_empty_stations,
  base.peak_empty_stations,
  base.snapshot_samples,
  info.total_stations_known,
  SAFE_DIVIDE(base.avg_stations_reporting, info.total_stations_known) as avg_coverage_ratio
FROM {{ ref('velib_totals_hourly_aggregate') }} base
CROSS JOIN (
  SELECT COUNT(DISTINCT station_id) as total_stations_known
  FROM {{ source('pmp_curated', 'velib_station_information') }}
) info
WHERE SAFE_DIVIDE(base.avg_stations_reporting, info.total_stations_known) >= 0.999
