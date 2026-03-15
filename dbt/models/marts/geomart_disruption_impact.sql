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
    d.from_stop_name,
    d.to_stop_name,
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
    -- Keep stations within 500 meters of the 'from' transit stop
    (d.from_geo IS NOT NULL AND v.station_geo IS NOT NULL AND ST_DWITHIN(d.from_geo, v.station_geo, 500))
    OR 
    -- Or stations within 500 meters of the 'to' transit stop
    (d.to_geo IS NOT NULL AND v.station_geo IS NOT NULL AND ST_DWITHIN(d.to_geo, v.station_geo, 500))
