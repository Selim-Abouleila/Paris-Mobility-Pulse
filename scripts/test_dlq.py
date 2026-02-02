#!/usr/bin/env python3
"""
Test script to verify DLQ functionality by publishing messages that should fail.
"""

import json
from datetime import datetime, timezone

from google.cloud import pubsub_v1

PROJECT_ID = "paris-mobility-pulse"
TOPIC_ID = "pmp-events"

publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)


def publish_message(msg_dict, description):
    """Publish a message to Pub/Sub"""
    payload_bytes = json.dumps(msg_dict, ensure_ascii=False).encode("utf-8")
    message_id = publisher.publish(topic_path, payload_bytes).result(timeout=10)
    print(f"✅ Published {description}: message_id={message_id}")
    return message_id


def test_parse_error():
    """Test 1: Invalid JSON - should fail at parse stage"""
    print("\n🧪 Test 1: Parse/Normalize Error (missing required fields)")

    # Missing required fields like 'payload', 'event_type'
    bad_msg = {
        "ingest_ts": datetime.now(timezone.utc).isoformat(),
        # Missing: event_ts, source, event_type, key, payload
    }

    publish_message(bad_msg, "PARSE ERROR (missing required fields)")


def test_transformation_error():
    """Test 2: Invalid payload structure - should fail at transformation"""
    print("\n🧪 Test 2: Transformation Error (stations not a list)")

    bad_msg = {
        "ingest_ts": datetime.now(timezone.utc).isoformat(),
        "event_ts": datetime.now(timezone.utc).isoformat(),
        "source": "velib",
        "event_type": "station_status_snapshot",
        "key": "velib:station_status_snapshot",
        "payload": {
            "data": {
                "stations": "NOT_A_LIST"  # Should be a list, not a string
            }
        },
    }

    publish_message(bad_msg, "TRANSFORM ERROR (stations not a list)")


def test_bq_schema_error():
    """Test 3: Schema mismatch - should fail at BigQuery insert"""
    print("\n🧪 Test 3: BigQuery Insert Error (invalid station data)")

    bad_msg = {
        "ingest_ts": datetime.now(timezone.utc).isoformat(),
        "event_ts": datetime.now(timezone.utc).isoformat(),
        "source": "velib",
        "event_type": "station_status_snapshot",
        "key": "velib:station_status_snapshot",
        "payload": {
            "data": {
                "stations": [
                    {
                        "station_id": 12345,
                        "num_bikes_available": "INVALID_NOT_INT",  # Should be int
                        "is_installed": "NOT_A_BOOLEAN",  # Should be 0 or 1
                        # Missing other required fields
                    }
                ]
            }
        },
    }

    publish_message(bad_msg, "BQ INSERT ERROR (schema mismatch)")


def test_valid_message():
    """Test 4: Valid message - should succeed"""
    print("\n✅ Test 4: Valid Message (should write to curated table)")

    good_msg = {
        "ingest_ts": datetime.now(timezone.utc).isoformat(),
        "event_ts": datetime.now(timezone.utc).isoformat(),
        "source": "velib",
        "event_type": "station_status_snapshot",
        "key": "velib:station_status_snapshot",
        "payload": {
            "data": {
                "stations": [
                    {
                        "station_id": 99999,
                        "stationCode": "99999-TEST",
                        "num_bikes_available": 5,
                        "num_docks_available": 10,
                        "is_installed": 1,
                        "is_renting": 1,
                        "is_returning": 1,
                        "last_reported": 1738511117,
                    }
                ]
            }
        },
    }

    publish_message(good_msg, "VALID MESSAGE (should succeed)")


if __name__ == "__main__":
    print("=" * 60)
    print("DLQ Test Script - Publishing Test Messages")
    print("=" * 60)

    print(f"\nProject: {PROJECT_ID}")
    print(f"Topic: {TOPIC_ID}")
    print(f"Topic Path: {topic_path}")

    # Run all tests
    test_parse_error()
    test_transformation_error()
    test_bq_schema_error()
    test_valid_message()

    print("\n" + "=" * 60)
    print("✅ All test messages published!")
    print("=" * 60)

    print("\n📊 Check DLQ table in ~1-2 minutes:")
    print("""
bq query --use_legacy_sql=false '
SELECT 
  dlq_ts,
  stage,
  error_type,
  SUBSTR(error_message, 1, 100) as error_msg,
  event_meta
FROM `paris-mobility-pulse.pmp_ops.velib_station_status_curated_dlq`
ORDER BY dlq_ts DESC
LIMIT 10'
""")

    print("\n📊 Check curated table for valid message:")
    print("""
bq query --use_legacy_sql=false '
SELECT station_id, station_code, ingest_ts
FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
WHERE station_id = \"99999\"
ORDER BY ingest_ts DESC
LIMIT 5'
""")
