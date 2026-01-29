#!/bin/bash
# Helper script to format the codebase

echo "Running Ruff format..."
ruff format .

echo "Running Terraform format..."
if command -v terraform &> /dev/null
then
    terraform fmt -recursive infra/terraform
else
    echo "Warning: terraform command not found. Skipping terraform formatting."
fi
