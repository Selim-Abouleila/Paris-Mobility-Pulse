import json
from typing import Any, Dict, Union

REQUIRED_FIELDS = ["ingest_ts", "event_ts", "source", "event_type", "key", "payload"]

def parse_event(raw: Union[str, bytes, Dict[str, Any]]) -> Dict[str, Any]:
    """
    Parse a single event from JSON string/bytes or dict.
    """
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8")

    if isinstance(raw, str):
        raw = raw.strip()
        if not raw:
            raise ValueError("Empty input line")
        obj = json.loads(raw)
    elif isinstance(raw, dict):
        obj = raw
    else:
        raise TypeError(f"Unsupported event type: {type(raw)}")

    if not isinstance(obj, dict):
        raise ValueError("Parsed event is not a JSON object")
    return obj

def normalize_event(evt: Dict[str, Any]) -> Dict[str, Any]:
    """
    Ensure required fields exist; safe defaults for early development.
    Later we can make validation stricter.
    """
    ingest_ts = evt.get("ingest_ts")
    if not ingest_ts:
        raise ValueError("Missing ingest_ts")

    # If event_ts missing, default to ingest_ts (common ingestion pattern)
    evt.setdefault("event_ts", ingest_ts)


    for k in ["source", "event_type", "key"]:
        if not evt.get(k):
            raise ValueError(f"Missing {k}")

    payload = evt.get("payload")
    if payload is None:
        raise ValueError("Missing payload")

    # Ensure payload is a dict-like JSON object for future BigQuery JSON column
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except Exception:
            # keep it as string but still store it
            payload = {"raw_payload": payload}
    if not isinstance(payload, (dict, list)):
        payload = {"value": payload}
    evt["payload"] = payload

    return evt