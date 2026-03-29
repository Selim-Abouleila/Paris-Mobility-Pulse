# 15 - ArcGIS Pro Integration

The **Paris Mobility Pulse** project supports direct, real-time integration with professional Geographic Information System (GIS) software like **ArcGIS Pro** via Google BigQuery. 

This enables urban planners to pull live disruption metrics directly into rich maps without needing to manually export shapefiles or rely strictly on web dashboards.

## Architecture

ArcGIS Pro connects to the `pmp_marts` (production) dataset via the **Magnitude Simba ODBC Driver for Google BigQuery**. 

Because ArcGIS relies heavily on unique integer identifiers and struggles with complex on-the-fly spatial aggregation, all spatial data prep is pushed upstream into **dbt**.

### The BigQuery -> ArcGIS Pipeline

1. **dbt Mart Models (`mart_disruption_impact_map`)** pre-calculate everything ArcGIS needs.
2. The **Simba ODBC Driver** communicates the BigQuery schema directly to the ArcGIS map canvas.
3. **Query Layers** inside ArcGIS Pro request the data live over the internet when the map is panned or zoomed. No data is stored locally.

---

## Pre-computed Spatial Features

To make the integration seamless, our core spatial view (`mart_disruption_impact_map`) natively outputs three key fields specifically designed for GIS software:

| Field | Type | Purpose |
|---|---|---|
| `objectid` | `INT64` | ArcGIS requires a strictly numeric, unique primary key to select and identify row features. We use `ABS(FARM_FINGERPRINT(id))` to generate this rapidly without breaking parallel processing. |
| `geom_point` | `GEOGRAPHY` (`Point`) | The exact coordinate of the disrupted transit stop. This powers standard point marker symbology. |
| `geom_polygon_750m` | `GEOGRAPHY` (`Polygon`) | A perfect 750-meter physical radius calculated using `ST_BUFFER()`. This allows GIS users to visualize the real-world blast radius impact mapped over the Paris street grid natively. |

## Query Layer Configuration

To map this data within ArcGIS Pro:

1. Create a **New Database Connection** pointing to the BigQuery instance using Service Account Authentication (Requires `roles/bigquery.dataViewer` and `roles/bigquery.jobUser`).
2. Add a **Query Layer**.
3. Use a basic `SELECT *` query since the dbt model has already handled all the heavy lifting:

```sql
SELECT * 
FROM `paris-mobility-pulse.pmp_marts.mart_disruption_impact_map`
```

4. Choose `objectid` as the **Unique Identifier**.
5. ArcGIS will detect *both* geometry fields. The GIS analyst can choose to render the `geom_point` (as bubbles) or the `geom_polygon_750m` (as transparent impact zones).

---

## Technical Restrictions Bypassed

By pushing the `ST_BUFFER` logic upstream to dbt, we bypass major ODBC restrictions. If an overarching `ST_BUFFER` command runs dynamically *inside* an ArcGIS Pro Query Layer, the ODBC driver assumes the geometry stream is too physically large (Large Results set) and attempts to create a staging `CREATE TABLE` inside BigQuery to cache the vertices.

This results in a `Permission bigquery.tables.create denied` error unless the read-only analyst is given full "Data Editor" rights.

Because dbt is executed by a service account that already has dataset Editor rights, pre-computing the geometries elegantly sidesteps the permission error, keeping our user-facing analytics accounts read-only and secure.
