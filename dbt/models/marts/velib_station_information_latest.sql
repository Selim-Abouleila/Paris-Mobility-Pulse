{{ config(materialized='view') }}

-- Latest station metadata per station_id.
-- velib_station_information is a slowly-changing feed; we select only the
-- most recent row per station to avoid fan-out when joining to status data.
SELECT * EXCEPT(rn)
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY station_id
            ORDER BY event_ts DESC, ingest_ts DESC
        ) AS rn
    FROM {{ source('pmp_curated', 'velib_station_information') }}
)
WHERE rn = 1
