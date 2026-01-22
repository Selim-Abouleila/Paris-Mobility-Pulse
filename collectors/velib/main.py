import os
import json
from datetime import datetime, timezone

import requests
from flask import Flask, jsonify

from google.cloud import pubsub_v1
import google.auth

app = Flask(__name__)

# Get project id reliably on Cloud Run
_, PROJECT_ID = google.auth.default()

TOPIC_ID = os.environ["TOPIC_ID"]
FEED_URL = os.environ["FEED_URL"]
SOURCE = os.environ.get("SOURCE", "velib")
EVENT_TYPE = os.environ.get("EVENT_TYPE", "station_status_snapshot")

publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)

@app.get("/healthz")
def healthz():
    return "ok", 200

@app.get("/collect")
def collect():
    ingest_ts = datetime.now(timezone.utc).isoformat()

    r = requests.get(FEED_URL, timeout=20)
    r.raise_for_status()
    data = r.json()

    # GBFS feeds usually provide last_updated (epoch seconds)
    event_ts = None
    if isinstance(data, dict) and "last_updated" in data:
        try:
            event_ts = datetime.fromtimestamp(data["last_updated"], tz=timezone.utc).isoformat()
        except Exception:
            event_ts = None

    msg = {
        "ingest_ts": ingest_ts,
        "event_ts": event_ts,
        "source": SOURCE,
        "event_type": EVENT_TYPE,
        "key": f"{SOURCE}:{EVENT_TYPE}",
        "payload": data,
    }

    payload_bytes = json.dumps(msg, ensure_ascii=False).encode("utf-8")
    message_id = publisher.publish(topic_path, payload_bytes).result(timeout=30)

    return jsonify({"status": "ok", "message_id": message_id})
