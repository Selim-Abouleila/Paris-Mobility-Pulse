{{ config(materialized='view') }}

WITH latest_disruptions AS (
  -- 1. Grab only the LATEST snapshot of each disruption
  SELECT *
  FROM {{ ref('stg_idfm_disruptions') }}
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY disruption_id 
    ORDER BY ingest_ts DESC
  ) = 1
),

flattened_sections AS (
  -- 2. Unnest the JSON array into individual rows
  SELECT
    disruption_id,
    ingest_ts,
    cause,
    severity,
    title,
    last_update,
    JSON_EXTRACT_SCALAR(section, '$.from.id') AS from_id_raw,
    JSON_EXTRACT_SCALAR(section, '$.to.id') AS to_id_raw
  FROM latest_disruptions,
  UNNEST(JSON_EXTRACT_ARRAY(impacted_sections)) AS section
),

extracted_keys AS (
  -- 3. Extract the numeric IDs (e.g., 'stop_area:IDFM:71337' -> 71337)
  --    These are ZdC IDs (Zones de Correspondance), NOT ZdA IDs
  SELECT
    *,
    CAST(REGEXP_EXTRACT(from_id_raw, r'stop_area:IDFM:(\d+)') AS INT64) AS from_zdc_id,
    CAST(REGEXP_EXTRACT(to_id_raw, r'stop_area:IDFM:(\d+)') AS INT64) AS to_zdc_id
  FROM flattened_sections
  WHERE REGEXP_EXTRACT(from_id_raw, r'stop_area:IDFM:(\d+)') IS NOT NULL
),

zdc_to_zda AS (
  -- 4. Bridge table: pick one ZdA per ZdC (multiple ZdA can share a ZdC)
  SELECT ZdCId, ZdAId
  FROM {{ ref('idfm_zones_darret') }}
  QUALIFY ROW_NUMBER() OVER(PARTITION BY ZdCId ORDER BY ZdAId) = 1
)

-- 5. Two-step join: ZdC → ZdA → stops reference (lat/lon)
SELECT
  e.disruption_id,
  e.cause,
  e.severity,
  e.title,
  e.last_update,
  
  -- From Stop
  e.from_zdc_id,
  r_from.name AS from_stop_name,
  r_from.lat  AS from_lat,
  r_from.lon  AS from_lon,
  
  -- To Stop
  e.to_zdc_id,
  r_to.name AS to_stop_name,
  r_to.lat  AS to_lat,
  r_to.lon  AS to_lon

FROM extracted_keys e
-- From: ZdC → ZdA → stops
LEFT JOIN zdc_to_zda z_from
  ON e.from_zdc_id = z_from.ZdCId
LEFT JOIN {{ ref('idfm_stops_reference') }} r_from
  ON z_from.ZdAId = r_from.zda_id
-- To: ZdC → ZdA → stops
LEFT JOIN zdc_to_zda z_to
  ON e.to_zdc_id = z_to.ZdCId
LEFT JOIN {{ ref('idfm_stops_reference') }} r_to
  ON z_to.ZdAId = r_to.zda_id

-- 6. Only keep disruptions that are actively affecting traffic right now
WHERE e.severity IN ('BLOQUANTE', 'PERTURBEE')
