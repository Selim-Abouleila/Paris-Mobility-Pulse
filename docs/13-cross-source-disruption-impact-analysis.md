# Cross-Source Analytics — Disruption Impact on Vélib

> [!IMPORTANT]
> This document describes the **analytical methodology** for measuring the impact of transit disruptions on Vélib bike availability. No implementation yet — this is the theory and design.

---

## 1. The Question

> *When a metro/RER line is disrupted, do nearby Vélib stations see a measurable spike in bike rentals compared to stations further away?*

---

## 2. Methodology: Spatial Control Group

Compare Vélib station availability **near** a disrupted transit stop vs. **far** from any disruption, at the **same point in time**.

### Why this approach?

| Approach | Pros | Cons |
|---|---|---|
| **Temporal** (same station, disrupted vs. normal day) | Simple | Confounded by weather, holidays, seasonality |
| **Spatial** (near vs. far, same time) ✅ | Controls for time-of-day, weather, events | Assumes "far" stations are unaffected |
| **Rate of depletion** (bikes/hour) | Shows dynamic effect | Requires minute-level time series analysis |

The spatial approach wins because it requires **no historical baseline** — the comparison happens within a single time window.

---

## 3. Definitions

### Impact Zone (Treatment Group)

Vélib stations within **500 meters** of any transit stop listed in the disruption's `impactedSections`.

```
Disruption: "Metro 7 — Opéra to Châtelet interrupted"
  → impacted stops: Opéra (48.87, 2.33), Châtelet (48.86, 2.35)
  → Impact Zone: all Vélib stations within 500m of either stop
```

### Control Zone

Vélib stations between **1,000m and 2,000m** from any impacted stop.

- **Why not > 2km?** Too far — different neighborhoods have different baseline usage patterns.
- **Why not 500m–1km?** Buffer zone to avoid spillover effects.

### Metric

**Bike availability ratio**: `num_bikes_available / capacity`

- Ranges from 0% (empty) to 100% (full)
- Normalizes across stations of different sizes

---

## 4. The Comparison

For each active disruption with severity `BLOQUANTE` or `PERTURBEE`:

```
┌─────────────────────────────────────────────────────────┐
│  Disruption: Metro 7 — BLOQUANTE — 8:00–10:00          │
│                                                         │
│  Impact Zone (< 500m):     avg 15% bikes remaining      │
│  Control Zone (1–2km):     avg 55% bikes remaining      │
│  ─────────────────────────────────────────               │
│  Δ = -40 percentage points                               │
│  Impact Score = 40pp fewer bikes near disrupted stops    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### SQL Sketch

```sql
WITH disrupted_stops AS (
  -- Flattened disruptions joined to stop coordinates
  SELECT d.disruption_id, d.severity, d.title,
         s.lat, s.lon, s.name AS stop_name
  FROM idfm_disruptions d
  JOIN idfm_stops_reference s ON d.from_stop_id = s.zda_id
  WHERE d.severity IN ('BLOQUANTE', 'PERTURBEE')
),

velib_near AS (
  -- Vélib stations within 500m of any disrupted stop
  SELECT v.station_id, v.num_bikes_available, v.capacity,
         'impact' AS zone
  FROM velib_latest_state_enriched v
  CROSS JOIN disrupted_stops ds
  WHERE ST_DISTANCE(
    ST_GEOGPOINT(ds.lon, ds.lat),
    ST_GEOGPOINT(v.lon, v.lat)
  ) < 500
),

velib_far AS (
  -- Vélib stations 1–2km from disrupted stops (control)
  SELECT v.station_id, v.num_bikes_available, v.capacity,
         'control' AS zone
  FROM velib_latest_state_enriched v
  CROSS JOIN disrupted_stops ds
  WHERE ST_DISTANCE(
    ST_GEOGPOINT(ds.lon, ds.lat),
    ST_GEOGPOINT(v.lon, v.lat)
  ) BETWEEN 1000 AND 2000
)

SELECT
  zone,
  COUNT(DISTINCT station_id) AS station_count,
  ROUND(AVG(SAFE_DIVIDE(num_bikes_available, capacity)) * 100, 1)
    AS avg_availability_pct
FROM (SELECT * FROM velib_near UNION ALL SELECT * FROM velib_far)
GROUP BY zone
```

### Expected Output

| Zone | Stations | Avg Availability |
|---|---|---|
| impact (< 500m) | 12 | 15.2% |
| control (1–2km) | 34 | 54.8% |

**Δ = -39.6 percentage points** → disruption signal confirmed.

---

## 5. Dashboard Panels

| Panel | Type | Description |
|---|---|---|
| Impact vs. Control gauge | Dual scorecard | Side-by-side: "Near disruption: 15%" vs. "Normal areas: 55%" |
| Map overlay | Map | Disrupted stops (🔴) + Vélib stations colored by availability (green → red) |
| Impact by severity | Bar chart | Average Δ for BLOQUANTE vs. PERTURBEE disruptions |
| Top impacted stations | Table | Vélib stations with lowest availability near active disruptions |

---

## 6. Prerequisites (What We Need)

| # | Dependency | Status |
|---|---|---|
| 1 | `stg_idfm_disruptions` (curated incremental table) | ✅ Done |
| 2 | `idfm_stops_reference` (seed with lat/lon) | ✅ Done |
| 3 | `idfm_disruptions` (flattened view, UNNEST + join stops) | ⬜ Next step |
| 4 | `disruptions_near_velib` (spatial join mart) | ⬜ After #3 |
| 5 | Dashboard panels | ⬜ After #4 |

---

## 7. Limitations & Caveats

- **Correlation ≠ causation** — low bike availability near a disrupted stop could also be caused by a nearby event, rain, or rush hour. The spatial control group mitigates this but doesn't eliminate it.
- **500m radius is arbitrary** — could be tuned. Paris blocks are ~100m, so 500m ≈ 5 blocks.
- **Not all disruptions divert to bikes** — a bus route disruption in the suburbs likely has no Vélib impact. Filtering to metro/RER `BLOQUANTE` disruptions in central Paris gives the strongest signal.
- **Vélib coverage** — some disrupted stops may not have Vélib stations nearby (suburban areas). The analysis naturally filters these out (empty impact zones).
