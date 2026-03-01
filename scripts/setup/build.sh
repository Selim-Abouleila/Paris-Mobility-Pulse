#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Build & Deploy Script
# Builds all Docker images and deploys them to Cloud Run.
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Environment Check
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/check_env.sh"
source .env

REGION="${REGION:-europe-west9}"

echo -e "${BLUE}==> Building & Deploying Container Images for Project: $PROJECT_ID${NC}"

# 2. Define Services to Build & Deploy
# Maps image name → source directory
declare -A IMAGES=(
    ["velib-collector"]="collectors/velib"
    ["station-info-writer"]="services/station-info-writer"
    ["bq-writer"]="services/bq-writer"
    ["idfm-collector"]="collectors/idfm"
)

# Maps image name → Cloud Run service name
declare -A SERVICES=(
    ["velib-collector"]="pmp-velib-collector"
    ["station-info-writer"]="pmp-velib-station-info-writer"
    ["bq-writer"]="pmp-bq-writer"
    ["idfm-collector"]="pmp-idfm-collector"
)

# 3. Build & Deploy Loop
for IMAGE_NAME in "${!IMAGES[@]}"; do
    SOURCE_DIR="${IMAGES[$IMAGE_NAME]}"
    SERVICE_NAME="${SERVICES[$IMAGE_NAME]}"
    FULL_IMAGE="gcr.io/$PROJECT_ID/$IMAGE_NAME:latest"
    
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo -e "${RED}ERROR: Source directory not found: $SOURCE_DIR${NC}"
        continue
    fi

    # Build
    echo -e "${BLUE}--> Building $IMAGE_NAME from $SOURCE_DIR...${NC}"
    gcloud builds submit "$SOURCE_DIR" \
        --tag "$FULL_IMAGE" \
        --project "$PROJECT_ID" \
        --quiet
    echo -e "${GREEN}    Built: $FULL_IMAGE${NC}"

    # Deploy to Cloud Run (forces new revision to pull the fresh image)
    echo -e "${BLUE}--> Deploying $SERVICE_NAME...${NC}"
    gcloud run deploy "$SERVICE_NAME" \
        --image "$FULL_IMAGE" \
        --region "$REGION" \
        --project "$PROJECT_ID" \
        --quiet
    echo -e "${GREEN}    Deployed: $SERVICE_NAME${NC}"
done

# 4. Build dbt Runner image (Cloud Run Job is created by Terraform)
echo -e "${BLUE}--> Building dbt-runner from dbt/...${NC}"
gcloud builds submit "dbt" \
    --tag "gcr.io/$PROJECT_ID/dbt-runner:latest" \
    --project "$PROJECT_ID" \
    --quiet
echo -e "${GREEN}    Built: gcr.io/$PROJECT_ID/dbt-runner:latest${NC}"

echo -e ""
echo -e "${GREEN}SUCCESS: All images built and deployed.${NC}"

