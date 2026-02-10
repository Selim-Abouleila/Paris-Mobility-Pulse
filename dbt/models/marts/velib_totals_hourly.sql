
SELECT
  base.*,
  DATETIME(base.hour_ts_paris, "Europe/Paris") as hour_paris,
  info.total_stations_known,
  SAFE_DIVIDE(base.avg_stations_reporting, info.total_stations_known) as avg_coverage_ratio
FROM {{ ref('velib_totals_hourly_aggregate') }} base
CROSS JOIN (
  SELECT COUNT(DISTINCT station_id) as total_stations_known
  FROM {{ source('pmp_curated', 'velib_station_information') }}
) info
