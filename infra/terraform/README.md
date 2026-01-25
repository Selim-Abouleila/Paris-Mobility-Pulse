# Paris Mobility Pulse - Terraform Infrastructure

This directory contains the Terraform configuration to manage the core infrastructure for the **Paris Mobility Pulse** project.

## Purpose (Phase 1)

This Terraform configuration manages the following resources:
*   **APIs Enablement**: Dataflow, Pub/Sub, BigQuery, Storage, IAM, Cloud Resource Manager.
*   **GCS Staging Bucket**: `gs://pmp-dataflow-paris-mobility-pulse` for Dataflow staging and temp files.
*   **Pub/Sub Subscription**: `pmp-events-dataflow-sub` (pull subscription) attached to the existing `pmp-events` topic.
    *   *Note: The `pmp-events` topic is pre-existing and not managed here; only the subscription is managed.*
*   **BigQuery**:
    *   Curated Dataset: `pmp_curated`
        *   Table: `velib_station_status` (partitioned by day, clustered by station_id)
    *   Marts Dataset: `pmp_marts`
        *   View: `velib_latest_state` (latest status per station)
*   **IAM & Service Accounts**:
    *   Service Account: `pmp-dataflow-sa` (Dataflow Worker)
    *   Roles: Dataflow Worker, Pub/Sub Subscriber/Viewer, BigQuery Data Editor, Storage Object Admin (bucket-scoped).

> **Note**: The running streaming Dataflow job is currently launched via the CLI (Python SDK) and is *not* yet managed by Terraform. Future phases may introduce Flex Templates and `google_dataflow_flex_template_job`.

## Prerequisites

*   **Terraform**: Version `>= 1.5`
*   **Google Cloud SDK**: Installed and authenticated.

### Authentication

1.  Login for Application Default Credentials (ADC) to run Terraform:
    ```bash
    gcloud auth application-default login
    gcloud config set project paris-mobility-pulse
    ```

2.  **Fix for "401 Anonymous caller":**
    If you encounter `gsutil: 401 Anonymous caller does not have storage.buckets.get` during plans/applies involving GCS, run:
    ```bash
    gcloud auth login --update-adc
    ```

## Quick Start

The provider is configured with defaults for `paris-mobility-pulse`.

1.  **Navigate to directory**:
    ```bash
    cd infra/terraform
    ```

2.  **Initialize**:
    ```bash
    terraform init
    ```

3.  **Import Existing Resources**:
    *If this is the first run, you must import existing manual resources. See the [Import Existing Resources](#import-existing-resources) section below.*

4.  **Plan**:
    ```bash
    terraform plan -var="project_id=paris-mobility-pulse" -var="region=europe-west9"
    ```

5.  **Apply**:
    ```bash
    terraform apply
    ```

## Import Existing Resources

Since some resources were created manually before Terraform, you must import them into your state to avoid errors or duplication.

**Prerequisite**: Run `terraform init` before importing.

**Recommended Import Order:**

1.  **GCS Staging Bucket**
    ```bash
    terraform import google_storage_bucket.dataflow_bucket pmp-dataflow-paris-mobility-pulse
    ```

2.  **BigQuery Dataset**
    ```bash
    terraform import google_bigquery_dataset.pmp_curated projects/paris-mobility-pulse/datasets/pmp_curated
    ```

3.  **BigQuery Table**
    ```bash
    terraform import google_bigquery_table.velib_station_status projects/paris-mobility-pulse/datasets/pmp_curated/tables/velib_station_status
    ```

4.  **Pub/Sub Subscription**
    ```bash
    terraform import google_pubsub_subscription.dataflow_sub projects/paris-mobility-pulse/subscriptions/pmp-events-dataflow-sub
    ```

5.  **Dataflow Worker Service Account**
    ```bash
    terraform import google_service_account.dataflow_sa projects/paris-mobility-pulse/serviceAccounts/pmp-dataflow-sa@paris-mobility-pulse.iam.gserviceaccount.com
    ```

6.  **BigQuery Marts Dataset**
    ```bash
    terraform import google_bigquery_dataset.pmp_marts projects/paris-mobility-pulse/datasets/pmp_marts
    ```

7.  **BigQuery Latest State View**
    ```bash
    terraform import google_bigquery_table.velib_latest_state projects/paris-mobility-pulse/datasets/pmp_marts/tables/velib_latest_state
    ```

## Validation After Apply

Verify the resources were correctly configured:

```bash
# Check Bucket
gsutil ls -b gs://pmp-dataflow-paris-mobility-pulse

# Check BigQuery Table partitions/clustering
bq show --format=prettyjson paris-mobility-pulse:pmp_curated.velib_station_status

# Check BigQuery Marts View
bq show --format=prettyjson paris-mobility-pulse:pmp_marts.velib_latest_state

# Check Pub/Sub Subscription
gcloud pubsub subscriptions describe pmp-events-dataflow-sub --project=paris-mobility-pulse

# View Terraform Outputs
terraform output
```

## Cost Control & Operations

*   **Bucket Lifecycle**: The staging bucket (`pmp-dataflow-...`) has a lifecycle rule that deletes objects under `temp/` and `staging/` after **7 days** to reduce costs.
*   **Dataflow Job**: The streaming job runs until cancelled. It is **not** stopped by Terraform.
    *   **Cost Saving**: The job is typically configured with `--max_num_workers=1` to control costs.
    *   **To Cancel (Console)**: Go to [Dataflow Jobs Console](https://console.cloud.google.com/dataflow/jobs), select the job, and click **Cancel**.
    *   **To Cancel (CLI)**:
        ```bash
        # List jobs to find the ID
        gcloud dataflow jobs list --project="paris-mobility-pulse" --region="europe-west9" --status=active

        # Cancel the specific job
        gcloud dataflow jobs cancel JOB_ID --project="paris-mobility-pulse" --region="europe-west9"
        ```

## Phase 1 vs Future

*   **Phase 1 (Current)**:
    *   **Scope**: Storage, Pub/Sub Subscription, BigQuery Datasets (Curated + Marts), IAM, and API enablement.
    *   **Pipeline**: Supports one streaming pipeline (Vélib status) that writes to one curated BigQuery table.
    *   **Marts**: `velib_latest_state` view provides the latest status per station for downstream consumption.

*   **Future**:
    *   **Sources**: Ingestion of multiple APIs (e.g., Station Information for static data).
    *   **Enrichment**: Pipelines joining `station_status` with `station_information` to add Lat/Lon context.
    *   **Architecture**: Dead Letter Queues (DLQ) for error handling, Data Marts for aggregated views.
    *   **Automation**: Fully managed Dataflow jobs using Terraform Flex Templates (`google_dataflow_flex_template_job`).
