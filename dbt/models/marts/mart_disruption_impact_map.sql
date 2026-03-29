{{ config(materialized='view') }}

-- Map-ready child of mart_disruption_impact_comparison.
-- Unpivots the two disruption stop points (from/to) into separate rows so that
-- spatial applications (ArcGIS Pro, Looker Studio) receive exactly ONE lat/lon pair per row.
-- Two rows are emitted per disruption: one for the from-stop, one for the to-stop.
-- 
-- ArcGIS Pro Pre-computations: 
-- This view pre-computes an integer `objectid` (required for ArcGIS Query Layers)
-- and the actual 750m impact zone polygon (`geom_polygon_750m`). Doing this in dbt 
-- avoids ODBC driver permission errors (`bigquery.tables.create denied`) that occur 
-- when ArcGIS attempts to run ST_BUFFER dynamically and cache the result in a temp table.

WITH base AS (
    SELECT * FROM {{ ref('mart_disruption_impact_comparison') }}
),

unpivoted AS (
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
)

SELECT
    -- Fast deterministic integer hash for ArcGIS Pro unique identifier
    ABS(FARM_FINGERPRINT(CONCAT(disruption_id, '_', stop_role))) AS objectid,
    *,
    -- Native point geometry
    ST_GEOGPOINT(lon, lat) AS geom_point,
    -- Pre-calculated 750-meter spatial footprint 
    ST_BUFFER(ST_GEOGPOINT(lon, lat), 750) AS geom_polygon_750m
FROM unpivoted
