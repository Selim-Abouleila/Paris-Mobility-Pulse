import argparse
import json
import os
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from datetime import datetime, timezone

from .transforms import parse_event, normalize_event


def _to_int(v):
    if v is None:
        return None
    try:
        return int(v)
    except Exception:
        return None

def _epoch_to_rfc3339(sec):
    if sec is None:
        return None
    try:
        return datetime.fromtimestamp(int(sec), tz=timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        return None

def _extract_bike_types(st):
    mech = None
    ebike = None
    types = st.get("num_bikes_available_types") or []

    if isinstance(types, list):
        for item in types:
            if not isinstance(item, dict):
                continue

            # Format you showed: [{"mechanical":12},{"ebike":0}]
            if "mechanical" in item:
                mech = _to_int(item.get("mechanical"))
            if "ebike" in item:
                ebike = _to_int(item.get("ebike"))

            # Alternate GBFS-style: {"bike_type":"mechanical","count":12}
            bt = item.get("bike_type")
            if bt and "count" in item:
                if bt == "mechanical":
                    mech = _to_int(item.get("count"))
                elif bt in ("ebike", "electric", "e-bike"):
                    ebike = _to_int(item.get("count"))

    return mech, ebike

def velib_snapshot_to_station_rows(evt):
    """
    Takes one envelope event whose payload is the full station_status snapshot,
    yields one dict row per station (curated).
    """
    payload = evt.get("payload") or {}
    data = payload.get("data") or {}
    stations = data.get("stations") or []

    ingest_ts = evt.get("ingest_ts")
    event_ts = evt.get("event_ts") or ingest_ts

    if not isinstance(stations, list):
        return

    for st in stations:
        if not isinstance(st, dict):
            continue

        station_id = st.get("station_id")
        if station_id is None:
            continue

        station_code = st.get("stationCode") or st.get("station_code") or st.get("stationCode".lower())

        num_bikes = st.get("num_bikes_available")
        if num_bikes is None:
            num_bikes = st.get("numBikesAvailable")

        num_docks = st.get("num_docks_available")
        if num_docks is None:
            num_docks = st.get("numDocksAvailable")

        mech, ebike = _extract_bike_types(st)

        yield {
            "ingest_ts": ingest_ts,
            "event_ts": event_ts,
            "station_id": str(station_id),
            "station_code": str(station_code) if station_code is not None else None,
            "is_installed": _to_int(st.get("is_installed")),
            "is_renting": _to_int(st.get("is_renting")),
            "is_returning": _to_int(st.get("is_returning")),
            "last_reported_ts": _epoch_to_rfc3339(st.get("last_reported")),
            "num_bikes_available": _to_int(num_bikes),
            "num_docks_available": _to_int(num_docks),
            "mechanical_available": mech,
            "ebike_available": ebike,
            "raw_station_json": json.dumps(st, ensure_ascii=False),
        }

def run(argv=None) -> None:
    parser = argparse.ArgumentParser(description="PMP Dataflow (Beam) pipeline - SAFE skeleton")
    parser.add_argument("--runner", default="DirectRunner", help="DirectRunner (default) or DataflowRunner")
    parser.add_argument("--allow_dataflow_runner", action="store_true",
                        help="Safety switch. Required to run DataflowRunner.")
    parser.add_argument("--local_input", default="samples/events.jsonl",
                        help="Local newline-delimited JSON input file (safe mode).")
    parser.add_argument("--local_output", default="/tmp/pmp_dataflow_out/out",
                        help="Local output prefix (safe mode).")

    parser.add_argument("--input_subscription", default="",
                        help="Pub/Sub subscription to read from. Example: projects/<project>/subscriptions/<sub>")
    parser.add_argument("--output_bq_table", default="",
                        help="BigQuery table spec: <project>:<dataset>.<table> (curated output).")

    args, beam_args = parser.parse_known_args(argv)

    # Safety: prevent accidental spend
    if args.runner.lower() != "directrunner" and not args.allow_dataflow_runner:
        raise SystemExit(
            "Refusing to run non-DirectRunner. "
            "If you REALLY want DataflowRunner, pass --allow_dataflow_runner explicitly."
        )

    # Beam pipeline options (keeps the door open for future DataflowRunner args)
    options = PipelineOptions(beam_args, runner=args.runner)

    # Ensure output dir exists
    out_dir = os.path.dirname(args.local_output)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    with beam.Pipeline(options=options) as p:
        if args.input_subscription:
            lines = (
                p
                | "ReadPubSub" >> beam.io.ReadFromPubSub(subscription=args.input_subscription)
                | "BytesToStr" >> beam.Map(lambda b: b.decode("utf-8"))
            )
        else:
            lines = p | "ReadLocalNDJSON" >> beam.io.ReadFromText(args.local_input)

        events = (
            lines
            | "ParseJSON" >> beam.Map(parse_event)
            | "NormalizeEvent" >> beam.Map(normalize_event)
        )

        station_rows = events | "VelibSnapshotToStations" >> beam.FlatMap(velib_snapshot_to_station_rows)

        if args.output_bq_table:
            station_rows | "WriteCuratedBQ" >> beam.io.WriteToBigQuery(
                table=args.output_bq_table,
                schema=(
                    "ingest_ts:TIMESTAMP,event_ts:TIMESTAMP,station_id:STRING,station_code:STRING,"
                    "is_installed:INT64,is_renting:INT64,is_returning:INT64,last_reported_ts:TIMESTAMP,"
                    "num_bikes_available:INT64,num_docks_available:INT64,mechanical_available:INT64,ebike_available:INT64,"
                    "raw_station_json:STRING"
                ),
                write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
                create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
            )
        else:
            (
                station_rows
                | "ToNDJSON" >> beam.Map(json.dumps)
                | "WriteLocal" >> beam.io.WriteToText(
                    args.local_output,
                    file_name_suffix=".jsonl",
                    shard_name_template="-SS-of-NN"
                )
            )

if __name__ == "__main__":
    run()