import argparse
import json
import os
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.io.gcp.bigquery_tools import RetryStrategy
from apache_beam.metrics import Metrics
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
        return (
            datetime.fromtimestamp(int(sec), tz=timezone.utc)
            .isoformat()
            .replace("+00:00", "Z")
        )
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

        station_code = (
            st.get("stationCode")
            or st.get("station_code")
            or st.get("stationCode".lower())
        )

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


class ParseNormalizeWithDlq(beam.DoFn):
    def __init__(self):
        self.dlq_count = Metrics.counter(self.__class__, "dlq_parse_normalize_count")

    def process(self, element):
        # input: raw line string
        raw_line = element
        try:
            # chain the existing logic
            evt = parse_event(raw_line)
            evt = normalize_event(evt)
            yield evt
        except Exception as e:
            self.dlq_count.inc()
            now_ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            # truncate raw line to 200k chars to avoid BQ row limit issues
            truncated_raw = raw_line[:200000] if isinstance(raw_line, str) else str(raw_line)[:200000]
            
            error_record = {
                "dlq_ts": now_ts,
                "stage": "parse_normalize",
                "error_type": type(e).__name__,
                "error_message": str(e),
                "raw": truncated_raw,
                "event_meta": None,
                "row_json": None,
                "bq_errors": None,
            }
            yield beam.pvalue.TaggedOutput("dlq", error_record)


class VelibSnapshotToStationsWithDlq(beam.DoFn):
    def __init__(self):
        self.dlq_count = Metrics.counter(self.__class__, "dlq_snapshot_mapping_count")

    def process(self, evt):
        # input: normalized event dict
        try:
            # 1. Filter checks
            # equivalent to existing logic check but explicitly mentioned in req
            if evt.get("event_type") != "velib_station_status":
                return

            # 2. Validation
            payload = evt.get("payload") or {}
            data = payload.get("data") or {}
            stations = data.get("stations")
            if not isinstance(stations, list):
                # If it's not a list, this transformer can't handle it -> DLQ it?
                # The prompt says "validate payload shape: payload.data.stations must be a list"
                # If not, it should raise or we raise manually to trigger catch block
                raise ValueError("payload.data.stations is not a list")

            # 3. Use existing logic to yield rows
            # We reuse the existing function which yields dicts
            for station_row in velib_snapshot_to_station_rows(evt):
                yield station_row

        except Exception as e:
            self.dlq_count.inc()
            now_ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            
            # Prepare contextual info
            raw_dump = json.dumps(evt, default=str)[:200000]
            
            # "event_meta = json.dumps({...})"
            meta = {
                "source": evt.get("source"),
                "event_type": evt.get("event_type"),
                "key": evt.get("key"),
                "ingest_ts": evt.get("ingest_ts"),
                "event_ts": evt.get("event_ts"),
            }
            
            error_record = {
                "dlq_ts": now_ts,
                "stage": "snapshot_to_station_rows",
                "error_type": type(e).__name__,
                "error_message": str(e),
                "raw": raw_dump,
                "event_meta": json.dumps(meta),
                "row_json": None,
                "bq_errors": None,
            }
            yield beam.pvalue.TaggedOutput("dlq", error_record)


class FormatBQFailures(beam.DoFn):
    def __init__(self):
        self.dlq_count = Metrics.counter(self.__class__, "dlq_bq_insert_count")

    def process(self, e):
        # Beam contract: (destination, row, errors)
        # destination: str, row: dict, errors: list[dict]
        self.dlq_count.inc()

        destination = e[0]
        row = e[1]
        errors = e[2]

        # Best-effort main error message
        error_message = None
        try:
            error_message = errors[0].get("message")
        except Exception:
            error_message = str(errors)

        now_ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

        yield {
            "dlq_ts": now_ts,
            "stage": "bq_insert_curated",
            "error_type": "BigQueryInsertError",
            "error_message": error_message,
            "raw": None,
            "event_meta": json.dumps({"destination": destination}, ensure_ascii=False),
            "row_json": json.dumps(row, ensure_ascii=False, default=str),
            "bq_errors": json.dumps(errors, ensure_ascii=False, default=str),
        }


def run(argv=None) -> None:
    parser = argparse.ArgumentParser(
        description="PMP Dataflow (Beam) pipeline - SAFE skeleton"
    )
    parser.add_argument(
        "--runner",
        default="DirectRunner",
        help="DirectRunner (default) or DataflowRunner",
    )
    parser.add_argument(
        "--allow_dataflow_runner",
        action="store_true",
        help="Safety switch. Required to run DataflowRunner.",
    )
    parser.add_argument(
        "--local_input",
        default="samples/events.jsonl",
        help="Local newline-delimited JSON input file (safe mode).",
    )
    parser.add_argument(
        "--local_output",
        default="/tmp/pmp_dataflow_out/out",
        help="Local output prefix (safe mode).",
    )

    parser.add_argument(
        "--input_subscription",
        default="",
        help="Pub/Sub subscription to read from. Example: projects/<project>/subscriptions/<sub>",
    )
    parser.add_argument(
        "--output_bq_table",
        default="",
        help="BigQuery table spec: <project>:<dataset>.<table> (curated output).",
    )
    parser.add_argument(
        "--dlq_bq_table",
        default="",
        help="BigQuery table spec for DLQ: <project>:<dataset>.<table>. If empty, DLQ writing is disabled.",
    )

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
                | "ReadPubSub"
                >> beam.io.ReadFromPubSub(subscription=args.input_subscription)
                | "BytesToStr" >> beam.Map(lambda b: b.decode("utf-8"))
            )
        else:
            lines = p | "ReadLocalNDJSON" >> beam.io.ReadFromText(args.local_input)

        # 1. Parse & Normalize with DLQ
        # Result is a PCollectionTuple with 'ok' (main) and 'dlq' (side output)
        parse_results = (
            lines
            | "ParseNormalizeWithDlq" >> beam.ParDo(ParseNormalizeWithDlq()).with_outputs("dlq", main="ok")
        )
        events = parse_results["ok"]
        parse_dlq = parse_results["dlq"]

        # 2. Transform to Station Rows with DLQ
        snapshot_results = (
            events 
            | "VelibSnapshotToStationsWithDlq" >> beam.ParDo(VelibSnapshotToStationsWithDlq()).with_outputs("dlq", main="ok")
        )
        station_rows = snapshot_results["ok"]
        snapshot_dlq = snapshot_results["dlq"]

        # 3. Write Curated to BQ with Failure Handling
        # We need a list to collect DLQ PCollections
        dlq_collections = [parse_dlq, snapshot_dlq]

        if args.output_bq_table:
            bq_write_result = (
                station_rows 
                | "WriteCuratedBQ" >> beam.io.WriteToBigQuery(
                    table=args.output_bq_table,
                    schema=(
                        "ingest_ts:TIMESTAMP,event_ts:TIMESTAMP,station_id:STRING,station_code:STRING,"
                        "is_installed:INT64,is_renting:INT64,is_returning:INT64,last_reported_ts:TIMESTAMP,"
                        "num_bikes_available:INT64,num_docks_available:INT64,mechanical_available:INT64,ebike_available:INT64,"
                        "raw_station_json:STRING"
                    ),
                    write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                    method=beam.io.WriteToBigQuery.Method.STREAMING_INSERTS,
                    insert_retry_strategy=RetryStrategy.RETRY_ON_TRANSIENT_ERROR,
                )
            )
            
            # Capture BQ insert failures
            # failed_rows_with_errors returns (destination, row_dict, errors_list)
            
            bq_errors_dlq = (
                bq_write_result.failed_rows_with_errors
                | "FormatBQFailures" >> beam.ParDo(FormatBQFailures())
            )
            
            dlq_collections.append(bq_errors_dlq)
            


        else:
            # Local write fallback (no BQ failure capture relevant here really, but keeping safe behavior)
            (
                station_rows
                | "ToNDJSON" >> beam.Map(json.dumps)
                | "WriteLocal"
                >> beam.io.WriteToText(
                    args.local_output,
                    file_name_suffix=".jsonl",
                    shard_name_template="-SS-of-NN",
                )
            )

        # 4. Write DLQ to BQ (if configured)
        if args.dlq_bq_table:
            all_dlq = (
                dlq_collections 
                | "FlattenDLQ" >> beam.Flatten()
            )
            
            (
                all_dlq
                | "WriteDLQ" >> beam.io.WriteToBigQuery(
                    table=args.dlq_bq_table,
                    schema=(
                        "dlq_ts:TIMESTAMP,stage:STRING,error_type:STRING,error_message:STRING,"
                        "raw:STRING,event_meta:STRING,row_json:STRING,bq_errors:STRING"
                    ),
                    write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                    method=beam.io.WriteToBigQuery.Method.STREAMING_INSERTS,
                    insert_retry_strategy=RetryStrategy.RETRY_ON_TRANSIENT_ERROR,
                )
            )

if __name__ == "__main__":
    run()
