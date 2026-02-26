{{
  config(
    materialized = 'table',
    partition_by = {
      "field": "ingest_ts",
      "data_type": "timestamp",
      "granularity": "month"
    },
    cluster_by = ["severity"]
  )
}}

SELECT
  ingest_ts,
  JSON_VALUE(payload, '$.id')           AS disruption_id,
  JSON_VALUE(payload, '$.cause')        AS cause,
  JSON_VALUE(payload, '$.severity')     AS severity,
  JSON_VALUE(payload, '$.title')        AS title,
  JSON_VALUE(payload, '$.shortMessage') AS short_message,
  JSON_VALUE(payload, '$.message')      AS message_html,
  PARSE_TIMESTAMP(
    '%Y%m%dT%H%M%S',
    JSON_VALUE(payload, '$.lastUpdate')
  ) AS last_update,
  JSON_QUERY(payload, '$.applicationPeriods') AS application_periods,
  JSON_QUERY(payload, '$.impactedSections')   AS impacted_sections
FROM {{ source('pmp_raw', 'idfm_disruptions_raw') }}
