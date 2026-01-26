# Vélib Station Information Pipeline

This pipeline collects **static station metadata** (name, location, capacity) from the Vélib Metropole API and stores it in BigQuery for enriching real-time status data.

## Architecture

```
Cloud Scheduler (daily 3:10 AM)
  ↓ OIDC Auth
Collector (Cloud Run)
  ↓ Publishes to
Pub/Sub Topic: pmp-velib-station-info
  ↓ Push Subscription with OIDC
Writer (Cloud Run)
  ↓ Inserts into
BigQuery: pmp_curated.velib_station_information
```

**Design Philosophy**: This pipeline uses **push subscription + Cloud Run** instead of a second always-on Dataflow job to control costs. Station information is nearly static (changes rarely), so daily collection is sufficient.

## Data Source

**Feed URL**: `https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_information.json`

**Update Frequency**: Daily at 3:10 AM Paris time (via Cloud Scheduler)

**API Format**: JSON endpoint following the [GBFS (General Bikeshare Feed Specification)](https://github.com/NABSA/gbfs) standard.

### Sample Response Structure

```json
{
  "data": {
    "stations": [
      {
        "station_id": 213688169,
        "stationCode": "16107",
        "name": "Benjamin Godard - Victor Hugo",
        "lat": 48.865983,
        "lon": 2.275725,
        "capacity": 35,
        "address": "52 RUE BENJAMIN GODARD - 75016 PARIS",
        "post_code": "75016"
      }
    ]
  }
}
```

## BigQuery Schema

**Dataset**: `pmp_curated`
**Table**: `velib_station_information`

| Field | Type | Mode | Description |
|-------|------|------|-------------|
| `ingest_ts` | TIMESTAMP | REQUIRED | When the pipeline ingested this event |
| `event_ts` | TIMESTAMP | NULLABLE | Event timestamp (same as ingest for snapshots) |
| `station_id` | STRING | REQUIRED | Unique station identifier |
| `station_code` | STRING | NULLABLE | Short station code (e.g., "16107") |
| `name` | STRING | NULLABLE | Human-readable station name |
| `lat` | FLOAT64 | NULLABLE | Latitude (WGS84) |
| `lon` | FLOAT64 | NULLABLE | Longitude (WGS84) |
| `capacity` | INT64 | NULLABLE | Total docking capacity |
| `address` | STRING | NULLABLE | Full street address |
| `post_code` | STRING | NULLABLE | Postal code |
| `raw_station_json` | STRING | NULLABLE | Original JSON for audit trail |

**Partitioning**: Day-partitioned on `ingest_ts`
**Clustering**: Clustered by `station_id` for efficient lookups

## Cloud Scheduler Configuration

**Job Name**: `pmp-velib-station-info-daily`
**Schedule**: `10 3 * * *` (Cron: Daily at 3:10 AM)
**Time Zone**: `Europe/Paris`
**Location**: `europe-west1` (Cloud Scheduler is a regional service)

> [!NOTE]
> **Why europe-west1?** Cloud Scheduler requires a valid regional location. While our Cloud Run services are in `europe-west9`, Cloud Scheduler is available in `europe-west1`, which is geographically close and well-supported.

**Authentication**: OIDC token with `pmp-scheduler-sa` service account

## Services

### Collector (`pmp-velib-station-info-collector`)

**Source Code**: `collectors/velib/`
**Runtime**: Cloud Run (Python Flask)
**Region**: `europe-west9`
**Service Account**: `pmp-collector-sa@paris-mobility-pulse.iam.gserviceaccount.com`

**Environment Variables**:
- `TOPIC_ID=pmp-velib-station-info`
- `FEED_URL=https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_information.json`
- `SOURCE=velib`
- `EVENT_TYPE=station_information_snapshot`

**Endpoints**:
- **GET /collect**: Fetches station_information.json and publishes to Pub/Sub
- **GET /healthz**: Health check

### Writer (`pmp-velib-station-info-writer`)

**Source Code**: `services/station-info-writer/`
**Runtime**: Cloud Run (Python Flask + gunicorn)
**Region**: `europe-west9`
**Service Account**: `pmp-station-info-writer-sa@paris-mobility-pulse.iam.gserviceaccount.com`

**Environment Variables**:
- `BQ_TABLE=paris-mobility-pulse.pmp_curated.velib_station_information`

**Endpoints**:
- **POST /pubsub**: Receives Pub/Sub push messages, flattens payload, inserts into BigQuery
- **GET /healthz**: Health check

## Verification

### 1. Check Latest Station Information

```sql
SELECT
  ingest_ts,
  station_id,
  station_code,
  name,
  lat,
  lon,
  capacity,
  post_code
FROM `paris-mobility-pulse.pmp_curated.velib_station_information`
ORDER BY ingest_ts DESC
LIMIT 20;
```

### 2. Count Unique Stations

```sql
SELECT COUNT(DISTINCT station_id) AS total_stations
FROM `paris-mobility-pulse.pmp_curated.velib_station_information`;
```

Expected: ~1,400 stations (as of 2026).

### 3. Verify Daily Updates

```sql
SELECT
  DATE(ingest_ts) AS ingest_date,
  COUNT(DISTINCT station_id) AS stations_count
FROM `paris-mobility-pulse.pmp_curated.velib_station_information`
GROUP BY ingest_date
ORDER BY ingest_date DESC
LIMIT 7;
```

### 4. Manual Trigger (Testing)

To test the pipeline without waiting for the scheduled run:

```bash
# Get the collector service URL
COLLECTOR_URL=$(gcloud run services describe pmp-velib-station-info-collector \
  --region=europe-west9 \
  --project=paris-mobility-pulse \
  --format='value(status.url)')

# Invoke with proper authentication
gcloud run services proxy pmp-velib-station-info-collector \
  --region=europe-west9 \
  --project=paris-mobility-pulse &

# In another terminal, call the endpoint
curl http://localhost:8080/collect
```

## Future Use: Enriched Mart

The station information table will be joined with `pmp_marts.velib_latest_state` to create an **enriched mart** that combines real-time status with static metadata:

```sql
CREATE OR REPLACE VIEW `pmp_marts.velib_latest_state_enriched` AS
SELECT
  s.*,
  i.name AS station_name,
  i.lat,
  i.lon,
  i.capacity,
  i.address,
  i.post_code
FROM `pmp_marts.velib_latest_state` s
LEFT JOIN (
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY station_id ORDER BY ingest_ts DESC) AS rn
    FROM `pmp_curated.velib_station_information`
  )
  WHERE rn = 1
) i
ON s.station_id = i.station_id;
```

**Benefits**:
- Add lat/lon for mapping and spatial analysis
- Add station names for user-friendly dashboards
- Add capacity for utilization calculations (bikes_available / capacity)

## Cost Optimization

This pipeline is designed to minimize costs:

1. **No Always-On Compute**: Collector runs only when triggered (daily), Writer runs only when messages arrive
2. **Push Subscription**: No need for a second streaming Dataflow job (which would cost ~$50-100/month)
3. **Daily Schedule**: Station metadata changes rarely, so daily updates are sufficient
4. **Efficient Storage**: BigQuery partitioning and clustering optimize query costs

**Estimated Monthly Cost**: < $1 USD (Cloud Run invocations + pub/sub messages + BigQuery storage)

## Troubleshooting

### Collector Not Triggered

Check Cloud Scheduler job status:
```bash
gcloud scheduler jobs describe pmp-velib-station-info-daily \
  --location=europe-west1 \
  --project=paris-mobility-pulse
```

View recent execution attempts:
```bash
gcloud scheduler jobs run pmp-velib-station-info-daily \
  --location=europe-west1 \
  --project=paris-mobility-pulse
```

### Writer Not Receiving Messages

Check subscription details:
```bash
gcloud pubsub subscriptions describe pmp-velib-station-info-to-bq-sub \
  --project=paris-mobility-pulse
```

Check for delivery errors:
```bash
gcloud pubsub subscriptions pull pmp-velib-station-info-to-bq-sub \
  --project=paris-mobility-pulse \
  --limit=5
```

### No Rows in BigQuery

1. Check Writer service logs:
   ```bash
   gcloud run services logs read pmp-velib-station-info-writer \
     --region=europe-west9 \
     --project=paris-mobility-pulse \
     --limit=50
   ```

2. Verify IAM permissions:
   ```bash
   gcloud projects get-iam-policy paris-mobility-pulse \
     --flatten="bindings[].members" \
     --filter="bindings.members:pmp-station-info-writer-sa@paris-mobility-pulse.iam.gserviceaccount.com"
   ```

3. Test BigQuery insert manually:
   ```bash
   bq query --use_legacy_sql=false \
     "SELECT COUNT(*) FROM \`paris-mobility-pulse.pmp_curated.velib_station_information\`"
   ```

## Related Documentation

- [00 - Bootstrap](00-bootstrap.md) - Initial project setup
- [01 - MVP Pipeline](01-mvp-pipeline.md) - Cloud Run ingestion for station_status
- [04 - Dataflow Curation](04-dataflow-curation.md) - Streaming processing for station_status
- [05 - BigQuery Marts](05-bigquery-marts-latest-state.md) - Analytics layer
