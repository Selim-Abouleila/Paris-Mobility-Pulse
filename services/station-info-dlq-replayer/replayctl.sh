#!/usr/bin/env bash
set -euo pipefail

# --------
# Station-Info DLQ Replayer - Ops CLI
# --------

PROJECT_ID="${PROJECT_ID:-paris-mobility-pulse}"
REGION="${REGION:-europe-west9}"
JOB_NAME="${JOB_NAME:-pmp-station-info-dlq-replayer}"

# service directory (where main.py + Procfile live)
SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pub/Sub resources
DLQ_SUB="${DLQ_SUB:-projects/${PROJECT_ID}/subscriptions/pmp-velib-station-info-push-dlq-hold-sub}"
DEST_TOPIC="${DEST_TOPIC:-projects/${PROJECT_ID}/topics/pmp-velib-station-info}"

# execution defaults (override by env vars when calling this script)
MAX_MESSAGES="${MAX_MESSAGES:-50}"
QPS="${QPS:-5}"
DRY_RUN="${DRY_RUN:-false}"
ACK_SKIPPED="${ACK_SKIPPED:-false}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  deploy       Deploy/update the Cloud Run Job from source (service folder)
  run          Execute replay now (REPLAY_ENABLED=true for this execution)
  dry-run      Execute replay in DRY_RUN=true mode (no publish/ack)
  pause        Pause replay by setting REPLAY_ENABLED=false on the Job
  resume       Resume replay by setting REPLAY_ENABLED=true on the Job
  status       Show job details (includes env vars)
  cancel       Cancel the most recent execution (hard stop)

Env overrides:
  PROJECT_ID REGION JOB_NAME DLQ_SUB DEST_TOPIC MAX_MESSAGES QPS DRY_RUN ACK_SKIPPED
EOF
}

cmd="${1:-}"
case "$cmd" in
  deploy)
    # Deploy from source (uses Procfile entrypoint).
    # We set REPLAY_ENABLED=false by default for safety; run uses per-execution override.
    gcloud run jobs deploy "$JOB_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --source="$SERVICE_DIR" \
      --set-env-vars="PROJECT_ID=$PROJECT_ID,DLQ_SUB=$DLQ_SUB,DEST_TOPIC=$DEST_TOPIC,REPLAY_ENABLED=false,MAX_MESSAGES=$MAX_MESSAGES,QPS=$QPS,DRY_RUN=$DRY_RUN,ACK_SKIPPED=$ACK_SKIPPED"
    ;;

  run)
    # Execute with overrides (only affects this execution).
    gcloud run jobs execute "$JOB_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --wait \
      --update-env-vars="REPLAY_ENABLED=true,MAX_MESSAGES=$MAX_MESSAGES,QPS=$QPS,DRY_RUN=$DRY_RUN,ACK_SKIPPED=$ACK_SKIPPED"
    ;;

  dry-run)
    gcloud run jobs execute "$JOB_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --wait \
      --update-env-vars="REPLAY_ENABLED=true,DRY_RUN=true,MAX_MESSAGES=$MAX_MESSAGES,QPS=$QPS,ACK_SKIPPED=$ACK_SKIPPED"
    ;;

  pause)
    # Update job env vars (creates a new revision).
    gcloud run jobs update "$JOB_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --update-env-vars="REPLAY_ENABLED=false"
    ;;

  resume)
    gcloud run jobs update "$JOB_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --update-env-vars="REPLAY_ENABLED=true"
    ;;

  status)
    gcloud run jobs describe "$JOB_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION"
    ;;

  cancel)
    # List executions, grab latest, cancel it.
    exec_name="$(gcloud run jobs executions list \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --job="$JOB_NAME" \
      --sort-by="~createTime" \
      --limit=1 \
      --format="value(name)" || true)"

    if [[ -z "${exec_name// }" ]]; then
      echo "No executions found for job: $JOB_NAME"
      exit 0
    fi

    echo "Cancelling execution: $exec_name"
    # Cancel command is documented.
    gcloud run jobs executions cancel "$exec_name" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --quiet
    ;;

  *)
    usage
    exit 1
    ;;
esac
