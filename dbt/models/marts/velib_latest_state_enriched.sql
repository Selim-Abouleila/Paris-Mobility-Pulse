{{ config(materialized='view') }}

-- Enriched real-time Vélib state: status + station metadata joined in one place.
-- Joins velib_latest_state (one row per station, most recent status) with
-- velib_station_information_latest (one row per station, most recent metadata)
-- to produce a single denormalised view ready for dashboards and downstream
-- spatial analysis.
SELECT
    s.*,
    i.name,
    i.lat,
    i.lon,
    i.capacity,
    i.address
FROM {{ ref('velib_latest_state') }} s
LEFT JOIN {{ ref('velib_station_information_latest') }} i
    USING (station_id)
