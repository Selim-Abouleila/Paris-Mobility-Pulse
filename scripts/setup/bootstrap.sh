#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Bootstrap Script
# Enables critical APIs and initializes Terraform.
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Run environment check first
# 1. Run environment check first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/check_env.sh"

# Global check: ensure we are at repo root by checking for .env
if [[ ! -f ".env" ]]; then
    # If not in CWD, maybe we are in scripts/setup?
    # But this script writes to infra/terraform, so we MUST be at root (or relative to root).
    echo -e "${RED}ERROR: .env not found.${NC}"
    echo "Please run this script from the repository root, e.g.: make bootstrap"
    exit 1
fi
source .env

echo -e "${BLUE}==> Bootstrapping project: $PROJECT_ID${NC}"

# 2. Enable Service Usage API first (required to enable other APIs)
echo -e "${BLUE}==> Enabling Service Usage API...${NC}"
gcloud services enable serviceusage.googleapis.com \
    cloudresourcemanager.googleapis.com \
    servicecontrol.googleapis.com \
    iam.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    containerregistry.googleapis.com \
    run.googleapis.com \
    cloudscheduler.googleapis.com \
    --project="$PROJECT_ID"

echo -e "${GREEN}  OK: Base APIs enabled.${NC}"

# 3. Create Terraform Variable file from .env
echo -e "${BLUE}==> Generating terraform.tfvars...${NC}"
cat > infra/terraform/terraform.tfvars <<EOF
project_id = "$PROJECT_ID"
region     = "$REGION"
EOF
echo -e "${GREEN}  OK: infra/terraform/terraform.tfvars created.${NC}"

# 4. Initialize Terraform
echo -e "${BLUE}==> Initializing Terraform...${NC}"
cd infra/terraform
terraform init -upgrade
cd ../..

echo -e ""
echo -e "${GREEN}SUCCESS: Bootstrap complete.${NC}"
echo -e "Run 'make deploy' to create infrastructure."
