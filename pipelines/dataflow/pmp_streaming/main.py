import argparse
import json
import os
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions

from .transforms import parse_event, normalize_event

def run(argv=None) -> None:
    parser = argparse.ArgumentParser(description="PMP Dataflow (Beam) pipeline - SAFE skeleton")
    parser.add_argument("--runner", default="DirectRunner", help="DirectRunner (default) or DataflowRunner")
    parser.add_argument("--allow_dataflow_runner", action="store_true",
                        help="Safety switch. Required to run DataflowRunner.")
    parser.add_argument("--local_input", default="samples/events.jsonl",
                        help="Local newline-delimited JSON input file (safe mode).")
    parser.add_argument("--local_output", default="/tmp/pmp_dataflow_out/out",
                        help="Local output prefix (safe mode).")

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
        lines = p | "ReadLocalNDJSON" >> beam.io.ReadFromText(args.local_input)

        events = (
            lines
            | "ParseJSON" >> beam.Map(parse_event)
            | "NormalizeEvent" >> beam.Map(normalize_event)
        )

        # For now: write locally, no BigQuery, no Pub/Sub
        (
            events
            | "ToNDJSON" >> beam.Map(json.dumps)
            | "WriteLocal" >> beam.io.WriteToText(
                args.local_output,
                file_name_suffix=".jsonl",
                shard_name_template="-SS-of-NN"
            )
        )

if __name__ == "__main__":
    run()