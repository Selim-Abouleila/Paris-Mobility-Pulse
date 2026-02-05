#!/usr/bin/env bash
set -eo pipefail

# -----------------------------------------------------------------------------
# Clean Project Resources Script
# WARNING: DELETES RESOURCES. Use to reset a project for Zero-Trust testing.
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

if [ -z "$PROJECT_ID" ]; then
    if [ -f "../../.env" ]; then
        source "../../.env"
    elif [ -f ".env" ]; then
        source ".env"
    else
        echo -e "${RED}ERROR: PROJECT_ID not found. Run from root or set env var.${RESET}"
        exit 1
    fi
fi

echo -e "${RED}!!! WARNING !!!${RESET}"
echo -e "You are about to DELETE infrastructure in project: ${YELLOW}$PROJECT_ID${RESET}"
echo -e "This is used to fix 'Already Exists' errors when Terraform state is lost."
echo -e "Resources to be deleted:"
echo -e " - BigQuery Datasets: pmp_raw, pmp_curated, pmp_marts, pmp_ops"
echo -e " - Pub/Sub Topics: pmp-events, pmp-velib-station-info*"
echo -e " - Service Accounts: pmp-* (dataflow, collector, writer, etc)"
echo -e " - Cloud Run Services: pmp-*"
echo -e " - Cloud Scheduler Jobs: pmp-*"
echo
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo -e "${YELLOW}==> Deleting BigQuery Datasets...${RESET}"
for ds in pmp_raw pmp_curated pmp_marts pmp_ops; do
    echo "    Removing $ds..."
    bq rm -r -f -d "$PROJECT_ID:$ds" 2>/dev/null || true
done

echo -e "${YELLOW}==> Deleting Pub/Sub Topics...${RESET}"
gcloud pubsub topics delete pmp-events --project="$PROJECT_ID" --quiet 2>/dev/null || true
gcloud pubsub topics delete pmp-velib-station-info --project="$PROJECT_ID" --quiet 2>/dev/null || true
gcloud pubsub topics delete pmp-velib-station-info-push-dlq --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo -e "${YELLOW}==> Deleting Cloud Run Services...${RESET}"
gcloud run services list --project="$PROJECT_ID" --format="value(name)" | grep "^pmp-" | while read -r svc; do
    echo "    Deleting Cloud Run service: $svc"
    gcloud run services delete "$svc" --region="$REGION" --project="$PROJECT_ID" --quiet
done || true

echo -e "${YELLOW}==> Deleting Cloud Scheduler Jobs...${RESET}"
# Default to europe-west1 if not set, as that is the project standard for schedulers
SCHED_LOCATION="${SCHED_LOCATION:-europe-west1}"

gcloud scheduler jobs list --location="$SCHED_LOCATION" --project="$PROJECT_ID" --format="value(name)" | grep "pmp-" | while read -r job; do
   echo "    Deleting Scheduler job: $job"
   gcloud scheduler jobs delete "$job" --location="$SCHED_LOCATION" --project="$PROJECT_ID" --quiet
done || true

echo -e "${YELLOW}==> Deleting Service Accounts...${RESET}"
SAs=("pmp-dataflow-sa" "pmp-collector-sa" "pmp-pubsub-push-sa" "pmp-scheduler-sa" "pmp-station-info-writer-sa" "pmp-bq-writer-sa")
for sa in "${SAs[@]}"; do
    email="$sa@$PROJECT_ID.iam.gserviceaccount.com"
    echo "    Deleting SA: $email"
    gcloud iam service-accounts delete "$email" --project="$PROJECT_ID" --quiet 2>/dev/null || true
done

echo -e "${GREEN}Cleanup complete. You can now run 'make deploy' cleanly.${RESET}"
