import base64
import json
import os
from datetime import datetime, timezone

from flask import Flask, request
from google.cloud import bigquery

app = Flask(__name__)
bq = bigquery.Client()

# Full table id: project.dataset.table
BQ_TABLE = os.environ.get(
    "BQ_TABLE",
    "paris-mobility-pulse.pmp_curated.velib_station_information"
)

def _now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

@app.get("/healthz")
def healthz():
    return ("ok", 200)

@app.post("/pubsub")
def pubsub():
    envelope = request.get_json(silent=True) or {}
    msg = (envelope.get("message") or {})
    data_b64 = msg.get("data")

    if not data_b64:
        return ("Bad Request: missing message.data", 400)

    try:
        event = json.loads(base64.b64decode(data_b64).decode("utf-8"))
    except Exception:
        app.logger.exception("Failed to decode pubsub message")
        return ("Bad Request: invalid base64/json", 400)

    ingest_ts = event.get("ingest_ts") or _now_iso()
    event_ts = event.get("event_ts") or ingest_ts

    payload = event.get("payload") or {}
    data = payload.get("data") or {}
    stations = data.get("stations") or []

    if not isinstance(stations, list):
        return ("Bad Request: payload.data.stations not a list", 400)

    rows = []
    for s in stations:
        if not isinstance(s, dict):
            continue

        station_id = s.get("station_id")
        if station_id is None or str(station_id).strip() == "":
            continue

        rows.append({
            "ingest_ts": ingest_ts,
            "event_ts": event_ts,
            "station_id": str(station_id),
            "station_code": str(s.get("stationCode") or s.get("station_code") or ""),
            "name": s.get("name"),
            "lat": s.get("lat"),
            "lon": s.get("lon"),
            "capacity": s.get("capacity"),
            "address": s.get("address"),
            "post_code": s.get("post_code") or s.get("postCode"),
            "raw_station_json": json.dumps(s, ensure_ascii=False),
        })

    if not rows:
        return ("", 204)

    errors = bq.insert_rows_json(BQ_TABLE, rows)
    if errors:
        app.logger.error("BigQuery insert errors: %s", errors)
        return ("BigQuery insert failed", 500)

    return ("", 204)
