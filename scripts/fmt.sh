#!/usr/bin/env bash
set -euo pipefail

ruff format .
ruff check .

if command -v terraform >/dev/null 2>&1; then
  (cd infra && terraform fmt -recursive)
else
  echo "terraform not installed; skipping terraform fmt"
fi
