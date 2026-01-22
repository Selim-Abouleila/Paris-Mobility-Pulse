import os
import json
import base64
import logging

from flask import Flask, request

from google.cloud import bigquery
import google.auth

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

_, PROJECT_ID = google.auth.default()
BQ_DATASET = os.environ["BQ_DATASET"]
BQ_TABLE = os.environ["BQ_TABLE"]

bq = bigquery.Client()
TABLE_ID = f"{PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}"

def norm_ts(ts):
    if ts is None:
        return None
    # BigQuery accepts RFC3339; this helps if you have "+00:00"
    if isinstance(ts, str) and ts.endswith("+00:00"):
        return ts[:-6] + "Z"
    return ts

@app.get("/healthz")
def healthz():
    return "ok", 200

@app.post("/pubsub")
def pubsub_push():
    envelope = request.get_json(silent=True)
    if not envelope or "message" not in envelope:
        logging.error("Invalid Pub/Sub push payload: %s", envelope)
        return ("Bad Request", 400)

    msg = envelope["message"]
    message_id = msg.get("messageId") or msg.get("message_id")

    data_b64 = msg.get("data")
    if not data_b64:
        logging.error("No data in message: %s", msg)
        return ("Bad Request", 400)

    # Decode Pub/Sub message payload
    try:
        raw = base64.b64decode(data_b64).decode("utf-8")
        event = json.loads(raw)
    except Exception as e:
        logging.exception("Failed to decode/parse message: %s", e)
        return ("Bad Request", 400)

    payload_val = event.get("payload")
    row = {
        "ingest_ts": norm_ts(event.get("ingest_ts")),
        "event_ts": norm_ts(event.get("event_ts")),
        "source": event.get("source"),
        "event_type": event.get("event_type"),
        "key": event.get("key"),
        "payload": json.dumps(payload_val, ensure_ascii=False) if isinstance(payload_val, (dict, list)) else payload_val,
    }

    # Use message_id as insertId to reduce duplicates on retries
    row_ids = [message_id] if message_id else [None]

    errors = bq.insert_rows_json(TABLE_ID, [row], row_ids=row_ids)
    if errors:
        logging.error("BigQuery insert errors: %s", errors)
        # Non-2xx => Pub/Sub will retry
        return ("BigQuery insert failed", 500)

    return ("", 204)
