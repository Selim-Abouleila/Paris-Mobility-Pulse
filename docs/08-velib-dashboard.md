# 08 - Vélib Dashboard (Looker Studio)

**Dashboard v1** provides a real-time window into the Paris Mobility Pulse data pipeline. It combines a live snapshot of station status with hourly trend analysis to visualize mobility patterns across Paris.

[**View Live Dashboard**](https://lookerstudio.google.com/reporting/40ae9759-385b-4b7f-9248-325390e3c5df)

![Vélib Dashboard v1](../images/pmp_velib_dash_1.png)

## Data Sources

The dashboard connects to BigQuery views managed by the project's Terraform configuration:

1.  **`pmp_marts.velib_latest_state`**:
    *   Provides the most recent status (bikes, docks) for every station.
    *   Used for the "Live Snapshot" KPIs and Map.
    *   One row per station.

2.  **Hourly Aggregates** (Planned/Optional):
    *   Trend charts currently derive insights from the raw/curated history or ad-hoc queries.
    *   Dedicated materialized views for hourly stats (`pmp_marts.velib_totals_hourly`) are planned for the next iteration to improve performance.

## Dashboard Sections

*   **Live Snapshot**: KPI cards showing total available mechanical bikes, e-bikes, docks, and stations reporting.
*   **Station Map**: Geospatial view of all stations, color-coded by availability.
*   **Hourly Availability Trends**: Time-series charts showing average, peak, and minimum bike availability over the last 24 hours.
*   **Empty Stations Trends**: Count of stations with 0 bikes available over time.
*   **Data Coverage**: Metrics on the ratio of stations reporting data.

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

*   **Early Data**: Charts may appear sparse or flat if the pipeline has just started.
*   **Latency**: Data freshness depends on Looker Studio's cache settings (usually 15 min) and the Dataflow pipeline's write frequency.
*   **Cost**: Continuous streaming (Dataflow) incurs costs. Use the demo controls to pause operations when not viewing the dashboard.

## Next Improvements

*   **Station Information**: Integrate `velib_station_information` for static metadata (names, capacity).
*   **Enriched Geo-Views**: Use `velib_latest_state_enriched` for better map filtering.
*   **Seasonality**: Add daily and weekly aggregation views for long-term trend analysis.
