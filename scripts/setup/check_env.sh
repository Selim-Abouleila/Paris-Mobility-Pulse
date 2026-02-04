#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Pre-flight Check
# ensures the environment is ready for 'make bootstrap' or 'make deploy'
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function fail() {
    echo -e "${RED}ERROR: $1${NC}"
    echo -e "${YELLOW}Hint: $2${NC}"
    exit 1
}

function check_cmd() {
    if ! command -v "$1" &> /dev/null; then
        fail "Missing command: $1" "Please install $1 and ensure it is in your PATH."
    fi
}

echo "==> 1. Checking required tools..."
check_cmd gcloud
check_cmd terraform
check_cmd python3
# jq is useful for JSON parsing in scripts, checking if we need it
if command -v jq &> /dev/null; then
   echo -e "${GREEN}  OK: jq found${NC}"
else
   echo -e "${YELLOW}  WARN: jq not found (recommended for some scripts)${NC}"
fi
echo -e "${GREEN}  OK: Core tools present.${NC}"

echo "==> 2. Checking configuration..."
if [[ ! -f ".env" ]]; then
    fail "No .env file found." "Run 'cp .env.example .env' and edit it to set your PROJECT_ID."
fi

# Load .env (but don't export everything to shell environment to avoid pollution, just read checks)
source .env

if [[ -z "${PROJECT_ID:-}" ]]; then
    fail "PROJECT_ID is not set in .env" "Edit .env and set PROJECT_ID=your-gcp-project-id"
fi
if [[ -z "${REGION:-}" ]]; then
    fail "REGION is not set in .env" "Edit .env and set REGION=europe-west9"
fi
echo -e "${GREEN}  OK: .env is valid.${NC}"

echo "==> 3. Checking Google Cloud Auth..."
# Check if logged in
if ! gcloud auth print-access-token &> /dev/null; then
    fail "Not authenticated with gcloud." "Run 'gcloud auth login' and 'gcloud auth application-default login'"
fi

# Check active project match
ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
if [[ "$ACTIVE_PROJECT" != "$PROJECT_ID" ]]; then
    fail "gcloud active project ($ACTIVE_PROJECT) does not match .env PROJECT_ID ($PROJECT_ID)" \
         "Run 'gcloud config set project $PROJECT_ID' to switch context."
fi
echo -e "${GREEN}  OK: gcloud authenticated and pointing to $PROJECT_ID${NC}"

echo "==> Environment looks good."
