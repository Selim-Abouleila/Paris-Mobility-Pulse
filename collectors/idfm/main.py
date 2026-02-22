import datetime
import json
import logging
import os

import requests
from flask import Flask, jsonify
from google.cloud import bigquery

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
PROJECT_ID = os.getenv("PROJECT_ID")
IDFM_API_KEY = os.getenv("IDFM_API_KEY")
IDFM_API_URL = (
    "https://prim.iledefrance-mobilites.fr/marketplace/disruptions_bulk/disruptions/v2"
)
BQ_TABLE = f"{PROJECT_ID}.pmp_raw.idfm_disruptions_raw"

if not PROJECT_ID:
    logger.error("PROJECT_ID environment variable is not set.")
    raise ValueError("PROJECT_ID must be set")

if not IDFM_API_KEY:
    logger.warning("IDFM_API_KEY environment variable is not set. API calls may fail.")

# Initialize BigQuery client
bq_client = bigquery.Client(project=PROJECT_ID)


@app.route("/", methods=["POST"])
def trigger_collection():
    """
    Cloud Scheduler triggers this endpoint via POST.
    Fetches disruptions from IDFM API and writes directly to BigQuery.
    """
    try:
        logger.info("Starting IDFM disruption collection...")

        headers = {"apikey": IDFM_API_KEY}

        response = requests.get(IDFM_API_URL, headers=headers, timeout=30)
        response.raise_for_status()

        data = response.json()
        disruptions = data.get("disruptions", [])

        logger.info(f"Fetched {len(disruptions)} disruptions.")

        now = datetime.datetime.utcnow().isoformat()

        # Build rows for BigQuery
        rows = []
        for disruption in disruptions:
            row = {
                "ingest_ts": now,
                "event_ts": now,
                "source": "idfm_disruptions",
                "event_type": "disruption",
                "key": disruption.get("id", "unknown"),
                "payload": json.dumps(disruption),
            }
            rows.append(row)

        if rows:
            errors = bq_client.insert_rows_json(BQ_TABLE, rows)
            if errors:
                logger.error(f"BigQuery insert errors: {errors}")
                return jsonify({"status": "error", "errors": errors}), 500

        logger.info(f"Inserted {len(rows)} rows into {BQ_TABLE}.")

        return jsonify({"status": "success", "inserted_count": len(rows)}), 200

    except Exception as e:
        logger.error(f"Error in collection: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
