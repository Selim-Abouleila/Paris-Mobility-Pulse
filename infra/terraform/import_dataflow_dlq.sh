#!/bin/bash
set -e

echo "====================================="
echo "Terraform Import: Dataflow Curated DLQ"
echo "====================================="

# Check if resources are already in state
echo ""
echo "Checking current state..."
terraform state list | grep -E "pmp_ops|velib_station_status_curated_dlq" || echo "No matching resources in state yet."

echo ""
echo "====================================="
echo "Step 1: Check if pmp_ops dataset is in state"
echo "====================================="

if terraform state list | grep -q "google_bigquery_dataset.pmp_ops"; then
  echo "✅ pmp_ops dataset is already in Terraform state."
else
  echo "⚠️  pmp_ops dataset NOT in Terraform state. Importing..."
  terraform import google_bigquery_dataset.pmp_ops projects/paris-mobility-pulse/datasets/pmp_ops
  echo "✅ Imported pmp_ops dataset."
fi

echo ""
echo "====================================="
echo "Step 2: Import DLQ table"
echo "====================================="

if terraform state list | grep -q "google_bigquery_table.velib_station_status_curated_dlq"; then
  echo "✅ velib_station_status_curated_dlq table is already in Terraform state."
else
  echo "⚠️  DLQ table NOT in Terraform state. Importing..."
  terraform import google_bigquery_table.velib_station_status_curated_dlq \\
    projects/paris-mobility-pulse/datasets/pmp_ops/tables/velib_station_status_curated_dlq
  echo "✅ Imported DLQ table."
fi

echo ""
echo "====================================="
echo "Step 3: Import IAM bindings (if not auto-created)"
echo "====================================="

echo "Note: IAM bindings are typically created fresh by Terraform."
echo "No import needed for new IAM bindings (google_bigquery_dataset_iam_member)."
echo "Terraform will add them to the dataset on next apply."

echo ""
echo "====================================="
echo "Import Complete!"
echo "====================================="
echo ""
echo "Next steps:"
echo "1. Run: terraform fmt"
echo "2. Run: terraform validate"  
echo "3. Run: terraform plan"
echo "4. Review plan carefully (should show minimal or no changes to existing resources)"
echo ""
