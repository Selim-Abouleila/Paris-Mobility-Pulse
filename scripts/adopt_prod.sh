#!/usr/bin/env bash
set -eo pipefail

# -----------------------------------------------------------------------------
# Adopt Production Resources Script
# Safely imports existing cloud resources into Terraform state.
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

if [ -z "$PROJECT_ID" ]; then
    if [ -f ".env" ]; then
        source .env
    else
        echo -e "${RED}ERROR: PROJECT_ID not found. Run from root or set env var.${RESET}"
        exit 1
    fi
fi

REGION="${REGION:-europe-west9}"
SCHED_LOCATION="${SCHED_LOCATION:-europe-west1}"

echo -e "${BLUE}==> Adopting existing resources for project: $PROJECT_ID${RESET}"
echo -e "${YELLOW}This script will import existing cloud resources into Terraform state.${RESET}"

cd infra/terraform

# Function to import resource if it exists in cloud but not in state
import_if_exists() {
    local tf_resource="$1"
    local cloud_id="$2"
    local desc="$3"

    echo -n "Checking $desc ($cloud_id)... "

    if terraform state show "$tf_resource" >/dev/null 2>&1; then
        echo -e "${GREEN}Already managed by Terraform.${RESET}"
        return
    fi

    echo -e "${YELLOW}Importing...${RESET}"
    if terraform import "$tf_resource" "$cloud_id"; then
        echo -e "${GREEN}  Success: Imported $tf_resource${RESET}"
    else
        echo -e "${RED}  Failed to import (or resource does not exist in cloud). Skipping.${RESET}"
    fi
}

# 1. BigQuery Datasets
echo -e "\n${BLUE}--> Adopting BigQuery Datasets${RESET}"
import_if_exists "google_bigquery_dataset.pmp_raw" "$PROJECT_ID:pmp_raw" "Raw Dataset"
import_if_exists "google_bigquery_dataset.pmp_curated" "$PROJECT_ID:pmp_curated" "Curated Dataset"
import_if_exists "google_bigquery_dataset.pmp_marts" "$PROJECT_ID:pmp_marts" "Marts Dataset"
import_if_exists "google_bigquery_dataset.pmp_ops" "$PROJECT_ID:pmp_ops" "Ops Dataset"

# 2. Pub/Sub Topics
echo -e "\n${BLUE}--> Adopting Pub/Sub Topics${RESET}"
import_if_exists "google_pubsub_topic.pmp_events" "projects/$PROJECT_ID/topics/pmp-events" "Events Topic"
import_if_exists "google_pubsub_topic.station_info_topic" "projects/$PROJECT_ID/topics/pmp-velib-station-info" "Station Info Topic"
import_if_exists "google_pubsub_topic.station_info_dlq_topic" "projects/$PROJECT_ID/topics/pmp-velib-station-info-push-dlq" "Station Info DLQ Topic"

# 3. GCS Buckets
echo -e "\n${BLUE}--> Adopting GCS Buckets${RESET}"
# Note: Bucket names are derived from variables, so we reconstruct them
DATAFLOW_BUCKET="pmp-dataflow-${PROJECT_ID}"
import_if_exists "google_storage_bucket.dataflow_bucket" "$DATAFLOW_BUCKET" "Dataflow Bucket"

# 4. Service Accounts
echo -e "\n${BLUE}--> Adopting Service Accounts${RESET}"
import_if_exists "google_service_account.dataflow_sa" "projects/$PROJECT_ID/serviceAccounts/pmp-dataflow-sa@$PROJECT_ID.iam.gserviceaccount.com" "Dataflow SA"
import_if_exists "google_service_account.collector_sa" "projects/$PROJECT_ID/serviceAccounts/pmp-collector-sa@$PROJECT_ID.iam.gserviceaccount.com" "Collector SA"
import_if_exists "google_service_account.pubsub_push_sa" "projects/$PROJECT_ID/serviceAccounts/pmp-pubsub-push-sa@$PROJECT_ID.iam.gserviceaccount.com" "Pub/Sub Push SA"
import_if_exists "google_service_account.scheduler_sa" "projects/$PROJECT_ID/serviceAccounts/pmp-scheduler-sa@$PROJECT_ID.iam.gserviceaccount.com" "Scheduler SA"
import_if_exists "google_service_account.station_info_writer_sa" "projects/$PROJECT_ID/serviceAccounts/pmp-station-info-writer-sa@$PROJECT_ID.iam.gserviceaccount.com" "Station Info Writer SA"

# 5. Cloud Run Services (Optional, as these are often ephemeral/redeployed)
echo -e "\n${BLUE}--> Adopting Cloud Run Services${RESET}"
import_if_exists "google_cloud_run_v2_service.pmp_velib_collector" "projects/$PROJECT_ID/locations/$REGION/services/pmp-velib-collector" "Velib Collector"
import_if_exists "google_cloud_run_v2_service.station_info_collector" "projects/$PROJECT_ID/locations/$REGION/services/pmp-station-info-collector" "Station Info Collector"
import_if_exists "google_cloud_run_v2_service.station_info_writer" "projects/$PROJECT_ID/locations/$REGION/services/pmp-station-info-writer" "Station Info Writer"
import_if_exists "google_cloud_run_v2_service.pmp_bq_writer" "projects/$PROJECT_ID/locations/$REGION/services/pmp-bq-writer" "BQ Writer"

# 6. Cloud Scheduler Jobs
echo -e "\n${BLUE}--> Adopting Cloud Scheduler Jobs${RESET}"
import_if_exists "google_cloud_scheduler_job.velib_poll_every_minute" "projects/$PROJECT_ID/locations/$SCHED_LOCATION/jobs/pmp-velib-poll-every-minute" "Poll Job"
import_if_exists "google_cloud_scheduler_job.station_info_daily" "projects/$PROJECT_ID/locations/$SCHED_LOCATION/jobs/pmp-velib-station-info-daily" "Station Info Job"

echo -e "\n${GREEN}Adoption Complete. You can now run 'make deploy' safely.${RESET}"
