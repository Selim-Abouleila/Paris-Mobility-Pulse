{{ config(materialized='view') }}

-- Current real-time state of every Vélib station.
-- Selects only the most recent status snapshot per station_id so downstream
-- models always see one row per station (no historical duplicates).
SELECT * EXCEPT(rn)
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY station_id
            ORDER BY event_ts DESC, ingest_ts DESC
        ) AS rn
    FROM {{ source('pmp_curated', 'velib_station_status') }}
)
WHERE rn = 1
