{{ config(materialized='view') }}

-- Map-ready child of mart_disruption_impact_comparison.
-- Unpivots the two disruption stop points (from/to) into separate rows so that
-- Looker Studio's Google Maps chart receives exactly ONE lat/lon pair per row.
-- Two rows are emitted per disruption: one for the from-stop, one for the to-stop.

WITH base AS (
    SELECT * FROM {{ ref('mart_disruption_impact_comparison') }}
)

-- From-stop row
SELECT
    disruption_id,
    disruption_title,
    cause,
    severity,
    last_update,
    'from' AS stop_role,
    from_stop_name  AS stop_name,
    from_lat        AS lat,
    from_lon        AS lon,
    stations_in_impact_zone,
    closest_station_distance_m,
    zone_fill_rate_pct,
    zone_avg_bikes_available,
    control_fill_rate_pct,
    control_avg_bikes_available,
    control_station_count,
    fill_rate_delta_pct
FROM base
WHERE from_lat IS NOT NULL AND from_lon IS NOT NULL

UNION ALL

-- To-stop row
SELECT
    disruption_id,
    disruption_title,
    cause,
    severity,
    last_update,
    'to' AS stop_role,
    to_stop_name    AS stop_name,
    to_lat          AS lat,
    to_lon          AS lon,
    stations_in_impact_zone,
    closest_station_distance_m,
    zone_fill_rate_pct,
    zone_avg_bikes_available,
    control_fill_rate_pct,
    control_avg_bikes_available,
    control_station_count,
    fill_rate_delta_pct
FROM base
WHERE to_lat IS NOT NULL AND to_lon IS NOT NULL
