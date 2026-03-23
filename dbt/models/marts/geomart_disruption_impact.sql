{{ config(materialized='view') }}

WITH disruptions AS (
    SELECT
        disruption_id,
        cause,
        severity,
        title,
        last_update,
        from_stop_name,
        from_lat,
        from_lon,
        to_stop_name,
        to_lat,
        to_lon,
        -- Create BigQuery Geography points safely
        CASE WHEN from_lon IS NOT NULL AND from_lat IS NOT NULL 
             THEN ST_GEOGPOINT(from_lon, from_lat) 
             ELSE NULL END AS from_geo,
        CASE WHEN to_lon IS NOT NULL AND to_lat IS NOT NULL 
             THEN ST_GEOGPOINT(to_lon, to_lat) 
             ELSE NULL END AS to_geo
    FROM {{ ref('idfm_disruptions') }}
    -- Only include disruptions from the most recent ingestion batch.
    -- Using MAX(ingest_ts) rather than CURRENT_TIMESTAMP() means the view
    -- stays populated even if the pipeline is paused for hours or days.
    -- Restrict to inner Paris where Vélib density is high enough for analysis.
    WHERE ingest_ts >= TIMESTAMP_SUB(
            (SELECT MAX(ingest_ts) FROM {{ ref('idfm_disruptions') }}),
            INTERVAL 30 MINUTE
          )
      AND from_lat BETWEEN 48.815 AND 48.910
      AND from_lon BETWEEN 2.250  AND 2.420
),

velib_stations AS (
    SELECT * EXCEPT(rn)
    FROM (
        SELECT
            station_id,
            station_code,
            name AS station_name,
            lat,
            lon,
            capacity,
            -- Create BigQuery Geography points safely
            CASE WHEN lon IS NOT NULL AND lat IS NOT NULL 
                 THEN ST_GEOGPOINT(lon, lat) 
                 ELSE NULL END AS station_geo,
            ROW_NUMBER() OVER (
                PARTITION BY station_id
                ORDER BY event_ts DESC, ingest_ts DESC
            ) AS rn
        FROM {{ source('pmp_curated', 'velib_station_information') }}
    )
    WHERE rn = 1
)

SELECT
    d.disruption_id,
    d.cause,
    d.severity,
    d.title,
    d.last_update,
    -- From stop
    d.from_stop_name,
    d.from_lat,
    d.from_lon,
    -- To stop
    d.to_stop_name,
    d.to_lat,
    d.to_lon,
    -- Vélib station
    v.station_id AS velib_station_id,
    v.station_code AS velib_station_code,
    v.station_name AS velib_station_name,
    v.capacity AS velib_station_capacity,
    -- Calculate exact distances
    ST_DISTANCE(d.from_geo, v.station_geo) AS distance_to_from_stop_meters,
    ST_DISTANCE(d.to_geo, v.station_geo) AS distance_to_to_stop_meters
FROM disruptions d
CROSS JOIN velib_stations v
WHERE 
    -- Keep stations within 750 metres of the 'from' transit stop
    (d.from_geo IS NOT NULL AND v.station_geo IS NOT NULL AND ST_DWITHIN(d.from_geo, v.station_geo, 750))
    OR 
    -- Or stations within 750 metres of the 'to' transit stop
    (d.to_geo IS NOT NULL AND v.station_geo IS NOT NULL AND ST_DWITHIN(d.to_geo, v.station_geo, 750))
