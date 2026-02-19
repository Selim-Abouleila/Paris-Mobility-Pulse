import os
import json
import logging
import requests
from flask import Flask, jsonify
from google.cloud import pubsub_v1
import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
PROJECT_ID = os.getenv("PROJECT_ID")
IDFM_API_KEY = os.getenv("IDFM_API_KEY")
TOPIC_ID = "pmp-events" # Hardcoded or env var? Let's use env var if reliable, but for now hardcode as in other collectors
IDFM_API_URL = "https://prim.iledefrance-mobilites.fr/marketplace/disruptions_bulk/disruptions/v2"

if not PROJECT_ID:
    logger.error("PROJECT_ID environment variable is not set.")
    raise ValueError("PROJECT_ID must be set")

if not IDFM_API_KEY:
    logger.warning("IDFM_API_KEY environment variable is not set. API calls may fail.")

# Initialize Pub/Sub Publisher
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)

@app.route("/", methods=["POST"])
def trigger_collection():
    """
    Cloud Scheduler triggers this endpoint via POST.
    Fetches disruptions from IDFM API and publishes to Pub/Sub.
    """
    try:
        logger.info("Starting IDFM disruption collection...")
        
        headers = {
            "apikey": IDFM_API_KEY
        }
        
        response = requests.get(IDFM_API_URL, headers=headers, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        disruptions = data.get("disruptions", [])
        
        logger.info(f"Fetched {len(disruptions)} disruptions.")
        
        # Publish each disruption as a separate message
        published_count = 0
        for disruption in disruptions:
            # Add metadata
            message_payload = {
                "source": "idfm_disruptions",
                "event_type": "disruption",
                "ingest_ts": datetime.datetime.utcnow().isoformat(),
                "payload": disruption
            }
            
            future = publisher.publish(
                topic_path, 
                json.dumps(message_payload).encode("utf-8"),
                source="idfm_collector",
                event_type="disruption"
            )
            published_count += 1
            
        logger.info(f"Published {published_count} messages to {topic_path}.")
        
        return jsonify({"status": "success", "published_count": published_count}), 200

    except Exception as e:
        logger.error(f"Error in collection: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
