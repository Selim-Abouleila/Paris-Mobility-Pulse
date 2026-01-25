# Terraform Infrastructure (Phase 1)

This configuration manages the infrastructure for the Paris Mobility Pulse Dataflow pipeline (Streaming).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- Authenticated `gcloud` session (`gcloud auth application-default login`)

## Quick Start

1. **Initialize**
   ```bash
   terraform init
   ```

2. **Plan**
   ```bash
   terraform plan
   ```

3. **Apply**
   ```bash
   terraform apply
   ```

## Import Existing Resources

Since some resources were created manually during Step 0-3, you likely need to import them into Terraform state to avoid "Already Exists" errors.

**1. Bucket:**
```bash
terraform import google_storage_bucket.dataflow_bucket pmp-dataflow-paris-mobility-pulse
```

**2. BigQuery:**
```bash
terraform import google_bigquery_dataset.pmp_curated projects/paris-mobility-pulse/datasets/pmp_curated
terraform import google_bigquery_table.velib_station_status projects/paris-mobility-pulse/datasets/pmp_curated/tables/velib_station_status
```

**3. Pub/Sub Subscription:**
```bash
terraform import google_pubsub_subscription.dataflow_sub projects/paris-mobility-pulse/subscriptions/pmp-events-dataflow-sub
```

## Phase 1 vs Future

**Phase 1** (Current):
- Single streaming job writing to one curated table.
- Infrastructure: 1 Bucket, 1 Subscription, 1 BQ Table, 1 SA.

**Future**:
- Expand to multiple sources (Weather, Traffic).
- Multiple sinks (Data Marts, DLQ).
- We may switch to individual Terraform modules or separate Dataflow jobs for isolation.
- **Note**: The running Dataflow job itself is NOT managed by Terraform yet. It is launched via CLI. In the future, we can use `google_dataflow_flex_template_job`.
