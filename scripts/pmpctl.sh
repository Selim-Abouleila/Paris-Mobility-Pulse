#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# Paris Mobility Pulse - Demo Control
# --------------------------


# Validates environment and loads variables if needed

# Validates environment and loads variables if needed
if [ -z "${PROJECT_ID:-}" ]; then
    if [ -f ".env" ]; then
        source .env
    elif [ -f "$(dirname "$0")/../.env" ]; then
        source "$(dirname "$0")/../.env"
    fi
fi

# Defaults (override by exporting env vars before running)
PROJECT_ID="${PROJECT_ID:-paris-mobility-pulse}"
REGION="${REGION:-europe-west9}"

# Cloud Scheduler is regional. Your README shows:
#   velib-poll-every-minute (location: europe-west1)
SCHED_LOCATION="${SCHED_LOCATION:-europe-west1}"

# Dataflow staging bucket
BUCKET="${BUCKET:-gs://pmp-dataflow-${PROJECT_ID}}"

# Dataflow input subscription + output table (from your README)
INPUT_SUB="${INPUT_SUB:-projects/${PROJECT_ID}/subscriptions/pmp-events-dataflow-sub}"
OUT_TABLE="${OUT_TABLE:-${PROJECT_ID}:pmp_curated.velib_station_status}"
DLQ_BQ_TABLE="${DLQ_BQ_TABLE-${PROJECT_ID}:pmp_ops.velib_station_status_curated_dlq}"
DATAFLOW_SA="${DATAFLOW_SA:-pmp-dataflow-sa@${PROJECT_ID}.iam.gserviceaccount.com}"
WORKER_ZONE="${WORKER_ZONE:-}"                 # empty means let Dataflow choose
WORKER_MACHINE_TYPE="${WORKER_MACHINE_TYPE:-}" # empty means default

# Scheduler jobs that control ingestion (add more later as you create them)
SCHED_JOBS=(
  "pmp-velib-poll-every-minute"      # station_status every minute
  "pmp-velib-station-info-daily"     # station_information daily (if created)
)

# Cloud Run collectors you may want to "poke" once during demo
RUN_COLLECTORS=(
  "pmp-velib-collector"              # station_status collector
  "pmp-velib-station-info-collector" # station_information collector
)

# Dataflow job naming
DATAFLOW_JOB_PREFIX="${DATAFLOW_JOB_PREFIX:-pmp-velib-curated-}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd))"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/logs}"
mkdir -p "$LOG_DIR"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

preflight() {
  need_cmd gcloud
  need_cmd python3

  # Ensure gcloud is pointed at the right project
  gcloud config set project "$PROJECT_ID" >/dev/null

  # Quick ADC check (common cause of gsutil/dataflow errors)
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "ERROR: ADC not set. Run:"
    echo "  gcloud auth application-default login"
    echo "If you see 'Anonymous caller' issues, also run:"
    echo "  gcloud auth login --update-adc"
    exit 1
  fi
}

job_exists_scheduler() {
  local job="$1"
  gcloud scheduler jobs describe "$job" \
    --project="$PROJECT_ID" \
    --location="$SCHED_LOCATION" >/dev/null 2>&1
}

scheduler_pause_all() {
  echo "==> Pausing Scheduler jobs (location=$SCHED_LOCATION)..."
  for job in "${SCHED_JOBS[@]}"; do
    if job_exists_scheduler "$job"; then
      gcloud scheduler jobs pause "$job" \
        --project="$PROJECT_ID" \
        --location="$SCHED_LOCATION" >/dev/null
      echo "  paused: $job"
    else
      echo "  (skip) scheduler job not found: $job"
    fi
  done
}

scheduler_resume_all() {
  echo "==> Resuming Scheduler jobs (location=$SCHED_LOCATION)..."
  for job in "${SCHED_JOBS[@]}"; do
    if job_exists_scheduler "$job"; then
      gcloud scheduler jobs resume "$job" \
        --project="$PROJECT_ID" \
        --location="$SCHED_LOCATION" >/dev/null
      echo "  resumed: $job"
    else
      echo "  (skip) scheduler job not found: $job"
    fi
  done
}

dataflow_list_running_ids() {
  # We cancel/list jobs by prefix to avoid killing future unrelated pipelines.
  # Output: one job id per line.
  gcloud dataflow jobs list \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format="csv[no-heading](id,name,state)" 2>/dev/null \
  | awk -F, -v prefix="$DATAFLOW_JOB_PREFIX" '
      $2 ~ "^"prefix && $3 ~ /Running/ {print $1}
    ' || true
}

dataflow_cancel_all() {
  echo "==> Cancelling running Dataflow jobs with prefix '$DATAFLOW_JOB_PREFIX' (region=$REGION)..."
  local ids
  ids="$(dataflow_list_running_ids || true)"
  if [[ -z "${ids// }" ]]; then
    echo "  no running jobs found"
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "  cancelling: $id"
    gcloud dataflow jobs cancel "$id" \
      --project="$PROJECT_ID" \
      --region="$REGION" >/dev/null || true
  done <<< "$ids"
}

dataflow_start_streaming_job() {
  # Don't start if one already running
  local existing
  existing="$(dataflow_list_running_ids || true)"
  if [[ -n "${existing// }" ]]; then
    echo "==> Dataflow job already running (prefix '$DATAFLOW_JOB_PREFIX'). Not starting a new one."
    echo "$existing" | sed 's/^/  running job id: /'
    return 0
  fi

  echo "==> Starting Dataflow streaming job (region=$REGION)..."
  local job_name="${DATAFLOW_JOB_PREFIX}$(date +%Y%m%d-%H%M%S)"
  local log_file="${LOG_DIR}/dataflow_${job_name}.log"

  echo "  job_name: $job_name"
  echo "  log:      $log_file"
  echo "  (this submits the job and keeps a local process running; we run it in background)"

  local worker_args=()
  if [[ -n "${WORKER_ZONE}" ]]; then
    worker_args+=(--worker_zone "$WORKER_ZONE")
  fi
  if [[ -n "${WORKER_MACHINE_TYPE}" ]]; then
    worker_args+=(--worker_machine_type "$WORKER_MACHINE_TYPE")
  fi


  (
    cd "$REPO_ROOT"
    nohup python3 -m pipelines.dataflow.pmp_streaming.main \
      --runner DataflowRunner \
      --allow_dataflow_runner \
      --project "$PROJECT_ID" \
      --region "$REGION" \
      "${worker_args[@]}" \
      --temp_location "$BUCKET/temp" \
      --staging_location "$BUCKET/staging" \
      --job_name "$job_name" \
      --service_account_email "$DATAFLOW_SA" \
      --streaming \
      --input_subscription "$INPUT_SUB" \
      --output_bq_table "$OUT_TABLE" \
      ${DLQ_BQ_TABLE:+--dlq_bq_table=$DLQ_BQ_TABLE} \
      --setup_file ./setup.py \
      --requirements_file pipelines/dataflow/pmp_streaming/requirements.txt \
      --num_workers 1 \
      --max_num_workers 1 \
      --autoscaling_algorithm=NONE \
      --save_main_session \
      >"$log_file" 2>&1 &
  )

  echo "  started. To watch submission logs:"
  echo "    tail -f \"$log_file\""
  echo "  To see job in console:"
  echo "    gcloud dataflow jobs list --project=\"$PROJECT_ID\" --region=\"$REGION\""
}

collect_now() {
  need_cmd curl

  echo "==> Triggering collectors once (manual 'demo poke')..."
  for svc in "${RUN_COLLECTORS[@]}"; do
    # Get URL
    local url
    url="$(gcloud run services describe "$svc" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --format="value(status.url)" 2>/dev/null || true)"

    if [[ -z "${url// }" ]]; then
      echo "  (skip) Cloud Run service not found: $svc"
      continue
    fi

    local token
    token="$(gcloud auth print-identity-token --audiences="$url")"

    echo "  calling: $svc -> $url/collect"
    curl -sS -H "Authorization: Bearer $token" "$url/collect" | sed 's/^/    /'
    echo
  done
}

status() {
  echo "PROJECT_ID=$PROJECT_ID"
  echo "REGION=$REGION"
  echo "SCHED_LOCATION=$SCHED_LOCATION"
  echo "DLQ_BQ_TABLE=$DLQ_BQ_TABLE"
  echo "WORKER_ZONE=$WORKER_ZONE"
  echo "WORKER_MACHINE_TYPE=$WORKER_MACHINE_TYPE"
  echo

  echo "==> Scheduler job states:"
  for job in "${SCHED_JOBS[@]}"; do
    if job_exists_scheduler "$job"; then
      local st
      st="$(gcloud scheduler jobs describe "$job" \
        --project="$PROJECT_ID" \
        --location="$SCHED_LOCATION" \
        --format="value(state)" || true)"
      echo "  $job: $st"
    else
      echo "  $job: (not found)"
    fi
  done
  echo

  echo "==> Running Dataflow jobs (prefix '$DATAFLOW_JOB_PREFIX'):"
  local ids
  ids="$(dataflow_list_running_ids || true)"
  if [[ -z "${ids// }" ]]; then
    echo "  none"
  else
    echo "$ids" | sed 's/^/  job id: /'
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  up|start        Resume schedulers + start Dataflow streaming job
  down|stop       Pause schedulers + cancel Dataflow streaming job(s)
  poke|collect    Trigger collectors once now (useful for demos)
  status          Show scheduler states + running Dataflow jobs

Env overrides:
  PROJECT_ID REGION SCHED_LOCATION BUCKET INPUT_SUB OUT_TABLE DATAFLOW_SA DLQ_BQ_TABLE WORKER_ZONE WORKER_MACHINE_TYPE
EOF
}

main() {
  preflight
  local cmd="${1:-}"
  case "$cmd" in
    up|start)
      scheduler_resume_all
      dataflow_start_streaming_job
      ;;
    down|stop)
      scheduler_pause_all
      dataflow_cancel_all
      ;;
    poke|collect)
      collect_now
      ;;
    status)
      status
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "${1:-}"
