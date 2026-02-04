#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Build Script
# Builds all Docker images found in the repository.
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Environment Check
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/check_env.sh"
source .env

echo -e "${BLUE}==> Building Container Images for Project: $PROJECT_ID${NC}"

# 2. Define Services to Build
# Format: "ImageName:DirectoryPath"
# We map the concise image name used in Terraform to the source directory.
declare -A IMAGES=(
    ["velib-collector"]="collectors/velib"
    ["station-info-writer"]="services/station-info-writer"
    ["bq-writer"]="services/bq-writer"
)

# 3. Build Loop
for IMAGE_NAME in "${!IMAGES[@]}"; do
    SOURCE_DIR="${IMAGES[$IMAGE_NAME]}"
    FULL_IMAGE="gcr.io/$PROJECT_ID/$IMAGE_NAME:latest"
    
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo -e "${RED}ERROR: Source directory not found: $SOURCE_DIR${NC}"
        continue
    fi

    echo -e "${BLUE}--> Building $IMAGE_NAME from $SOURCE_DIR...${NC}"
    
    # Check if Cloud Build is enabled (handled in bootstrap, but good to fail fast)
    
    gcloud builds submit "$SOURCE_DIR" \
        --tag "$FULL_IMAGE" \
        --project "$PROJECT_ID" \
        --quiet
        
    echo -e "${GREEN}    Success: $FULL_IMAGE${NC}"
done

echo -e ""
echo -e "${GREEN}SUCCESS: All images built and pushed.${NC}"
