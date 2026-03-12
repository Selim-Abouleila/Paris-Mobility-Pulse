
SELECT
  base.*,
  DATETIME(base.hour_ts_paris, "Europe/Paris") as hour_paris,
  SAFE_DIVIDE(base.avg_stations_reporting, base.total_stations_known) as avg_coverage_ratio
FROM {{ ref('velib_totals_hourly_aggregate') }} base
