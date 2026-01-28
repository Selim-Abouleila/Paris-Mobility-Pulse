# 08 - Vélib Dashboard (Looker Studio)

**Dashboard v1** provides a real-time window into the Paris Mobility Pulse data pipeline. It combines a live snapshot of station status with hourly trend analysis to visualize mobility patterns across Paris.

[**View Live Dashboard**](https://lookerstudio.google.com/reporting/40ae9759-385b-4b7f-9248-325390e3c5df)

![Vélib Dashboard v1](../images/pmp_velib_dash_1.png)

### Dashboard Preview (v1)

![Vélib Trends & Dynamics (Hourly)](../images/pmp_velib_dash_2.png)

## Analysis: Real-World Patterns

The "Vélib Trends & Dynamics" charts (captured in `pmp_velib_dash_2.png`) provide a textbook visualization of Paris's daily rhythm. The data is highly congruent with actual urban mobility patterns:

*   **The Morning Commute (8 AM - 9 AM)**: You can see a sharp, synchronous dip in "Average Total Bikes" as thousands of Parisians unlock bikes simultaneously to reach offices and schools. This is mirrored by a surge in "Empty-Station Pressure" as popular destination hubs (like Saint-Lazare or La Défense) reach capacity or origin stations run dry.
*   **The Midday Plateau**: Availability stabilizes between 10 AM and 4 PM as bikes are redistributed or parked.
*   **The Evening Rush (5 PM - 7 PM)**: A second distinct "V-shape" dip occurs during the return commute. The pressure on empty stations spikes again, showing the system-wide strain during peak transition hours.
*   **Nightly Reset**: The curve gradually rises after 11 PM as maintenance teams and natural redistribution return bikes to the network, preparing for the next morning's cycle.

## Data Sources & Lineage

The dashboard connects to BigQuery views managed by the project's Terraform configuration. We use a multi-layer strategy to balance query performance and presentation logic:

### Data Lineage Table

| Object Name | Layer | Source | Purpose |
| :--- | :--- | :--- | :--- |
| `velib_station_status` | **Curated** | Dataflow | Cleaned, deduplicated streaming status updates. |
| `velib_totals_hourly` | **Marts (Base)** | Curated | Aggregated trends (Materialized View). |
| `velib_totals_hourly_paris` | **Marts (Dash)** | Marts (Base) | Wrapper for Looker Studio; adds Paris-local DATETIME and coverage ratios. |
| `velib_latest_state` | **Marts (Live)** | Curated | Latest snapshot per station (windowing logic). |

### Design Rationale: Mirroring Materialized Views

We implement the hourly trends using a **two-layer "Virtualized" approach** instead of a single massive query:

1.  **The Base Aggregate (`velib_totals_hourly`)**: Performs the heavy lifting (time truncation, snapshot-level math) as a **Materialized View**, ensuring high-performance pre-computing.
2.  **The Consumer Wrapper (`velib_totals_hourly_paris`)**: Handles Looker-specific requirements like the `hour_paris` (DATETIME) conversion and joining with `velib_station_information`. This keeps the "heavy" logic isolated from "presentation" logic, reducing query maintenance overhead.

## Dashboard Sections

*   **Live Snapshot**: KPI cards showing total available mechanical bikes, e-bikes, docks, and stations reporting.
*   **Station Map**: Geospatial view of all stations, color-coded by availability.
*   **Hourly Availability Trends**: Time-series charts driven by `velib_totals_hourly_paris` showing:
    *   `avg_total_bikes_available`
    *   `peak_total_bikes_available`
    *   `min_total_bikes_available`
*   **Empty Stations Trends**: Count of stations with 0 bikes available over time (`avg_empty_stations`, `peak_empty_stations`).
*   **Data Coverage**: Metrics on the ratio of stations reporting data (`avg_stations_reporting` / `total_stations_known`).

### Timezone Note

The BigQuery source data stores timestamps in UTC. To ensure charts display correctly in the dashboard:
*   We output an **`hour_paris`** (DATETIME) field in the `velib_totals_hourly_paris` view.
*   This pre-converts UTC timestamps to **Europe/Paris** time, simplifying Looker Studio's time handling.

## How to Run (End-to-End)

To populate the dashboard with live data, start the pipeline using the operation control script:

```bash
# Start ingestion and Dataflow processing
./scripts/pmpctl.sh up

# (Optional) Trigger an immediate collection
./scripts/pmpctl.sh collect
```

> **Note**: For meaningful hourly patterns, let the pipeline run for at least 24 hours.

When finished, stop cost-generating resources:

```bash
./scripts/pmpctl.sh down
```

## Known Limitations

*   **Freshness**: Data follows the pipeline's end-to-end latency (Collector -> Pub/Sub -> Dataflow -> BigQuery). Looker Studio's cache typically adds ~15 minutes of delay.
*   **Historical Depth**: Trend charts rely on the duration for which the pipeline has been active. Short-term runs may show incomplete daily cycles.
*   **Cost Management**: Continuous streaming incurs ongoing GCP costs. The dashboard data flow is managed via `pmpctl.sh` to ensure visibility during demos while maintaining fiscal responsibility.

## Next Improvements

*   **Dimension Enrichment**: Joining with `velib_station_information` to aggregate metrics by Paris Arrondissement.
*   **Materialized View Optimization**: Shifting from standard views to Materialized Views for the hourly aggregate to further reduce query costs.
*   **Seasonal Baseline**: Adding year-over-year or month-over-month comparisons as the data lake grows.
