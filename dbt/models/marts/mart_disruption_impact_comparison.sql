{{ config(materialized='view') }}

-- Compares Vélib bike availability inside active disruption zones against a
-- spatial control group (all stations NOT near any active disruption).
-- One row per unique physical disruption (deduplicated by title + stop pair).
--
-- NOTE: A temporal baseline (same station, same hour, same weekday, no disruption)
-- is architecturally superior but requires ≥4 weeks of continuous pipeline history.
-- Revisit once sufficient history accumulates.

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Active disruptions with nearby Vélib stations (from geomart)
-- ─────────────────────────────────────────────────────────────────────────────
WITH geomart AS (
    SELECT
        g.disruption_id,
        g.title         AS disruption_title,
        g.cause,
        g.severity,
        g.last_update,
        g.from_stop_name,
        g.from_lat,
        g.from_lon,
        g.to_stop_name,
        g.to_lat,
        g.to_lon,
        g.velib_station_id,
        LEAST(g.distance_to_from_stop_meters, g.distance_to_to_stop_meters)
            AS nearest_stop_distance_m
    FROM {{ ref('geomart_disruption_impact') }} g
    -- Deduplicate: IDFM sometimes re-notifies the same physical disruption
    -- (same route + same stop pair) with a new disruption_id each day.
    -- Keep only the most recent instance per unique (title, from_stop, to_stop).
    -- Using LEAST/GREATEST forces A->B and B->A into the exact same partition.
    -- adding from_stop_name ASC into ORDER BY makes the tie-breaker deterministic
    -- so every velib station picks the exact SAME direction orientation!
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY 
            g.title, 
            LEAST(g.from_stop_name, g.to_stop_name),
            GREATEST(g.from_stop_name, g.to_stop_name),
            g.velib_station_id
        ORDER BY g.last_update DESC, g.from_stop_name ASC
    ) = 1
),

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: All stations with their live fill rate
-- ─────────────────────────────────────────────────────────────────────────────
stations AS (
    SELECT
        station_id,
        num_bikes_available,
        num_docks_available,
        capacity,
        SAFE_DIVIDE(num_bikes_available, NULLIF(capacity, 0)) AS fill_rate
    FROM {{ ref('velib_latest_state_enriched') }}
    WHERE capacity > 0
),

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3: The "impacted pool" — any station near ANY active disruption
-- ─────────────────────────────────────────────────────────────────────────────
impacted_station_ids AS (
    SELECT DISTINCT velib_station_id AS station_id
    FROM geomart
),

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 4: Control group — stations NOT near any active disruption
-- ─────────────────────────────────────────────────────────────────────────────
control_stats AS (
    SELECT
        AVG(fill_rate)              AS control_avg_fill_rate,
        AVG(num_bikes_available)    AS control_avg_bikes_available,
        COUNT(*)                    AS control_station_count
    FROM stations s
    WHERE s.station_id NOT IN (SELECT station_id FROM impacted_station_ids)
),

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 5: Per-disruption impact zone stats
-- ─────────────────────────────────────────────────────────────────────────────
disruption_zone_stats AS (
    SELECT
        g.disruption_id,
        g.disruption_title,
        g.cause,
        g.severity,
        g.last_update,
        g.from_stop_name,
        g.from_lat,
        g.from_lon,
        g.to_stop_name,
        g.to_lat,
        g.to_lon,
        COUNT(DISTINCT g.velib_station_id)  AS stations_in_impact_zone,
        AVG(s.fill_rate)                    AS zone_avg_fill_rate,
        AVG(s.num_bikes_available)          AS zone_avg_bikes_available,
        MIN(g.nearest_stop_distance_m)      AS closest_station_distance_m
    FROM geomart g
    LEFT JOIN stations s ON g.velib_station_id = s.station_id
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
)

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 6: Final comparison — disruption zone vs spatial control group
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    d.disruption_id,
    d.disruption_title,
    d.cause,
    d.severity,
    d.last_update,
    d.from_stop_name,
    d.from_lat,
    d.from_lon,
    d.to_stop_name,
    d.to_lat,
    d.to_lon,
    d.stations_in_impact_zone,
    d.closest_station_distance_m,
    ROUND(d.zone_avg_fill_rate * 100, 1)         AS zone_fill_rate_pct,
    ROUND(d.zone_avg_bikes_available, 1)          AS zone_avg_bikes_available,
    ROUND(c.control_avg_fill_rate * 100, 1)       AS control_fill_rate_pct,
    ROUND(c.control_avg_bikes_available, 1)       AS control_avg_bikes_available,
    c.control_station_count,
    ROUND((d.zone_avg_fill_rate - c.control_avg_fill_rate) * 100, 1)
        AS fill_rate_delta_pct

FROM disruption_zone_stats d
CROSS JOIN control_stats c
ORDER BY fill_rate_delta_pct ASC
