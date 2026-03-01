# Dataflow Worker Service Account
resource "google_service_account" "dataflow_sa" {
  account_id   = "pmp-dataflow-sa"
  display_name = "Dataflow Worker Service Account"
}

# IAM Roles for Dataflow Worker
resource "google_project_iam_member" "dataflow_worker" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "pubsub_viewer" {
  project = var.project_id
  role    = "roles/pubsub.viewer"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Dataflow SA: Dataset-level permissions (Hardened)
# Needs to read from events (via Pub/Sub, already covered) 
# Needs to write to Curated (velib_station_status)
resource "google_bigquery_dataset_iam_member" "dataflow_sa_curated_editor" {
  dataset_id = google_bigquery_dataset.pmp_curated.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Needs to read Raw (if backfill/replay needed) - granting viewer just in case
resource "google_bigquery_dataset_iam_member" "dataflow_sa_raw_viewer" {
  dataset_id = google_bigquery_dataset.pmp_raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Bucket level permissions (Scoped to the specific bucket)
resource "google_storage_bucket_iam_member" "worker_storage_admin" {
  bucket = google_storage_bucket.dataflow_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Allow Dataflow Service Agent to impersonate the Worker SA
data "google_project" "project" {}

resource "google_service_account_iam_member" "dataflow_service_agent_impersonation" {
  service_account_id = google_service_account.dataflow_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.project.number}@dataflow-service-producer-prod.iam.gserviceaccount.com"
}

# ========================
# Station Information Pipeline Service Accounts & IAM
# ========================

# Reference existing service accounts (created manually, not managed by this TF)
# Service Accounts (Migrated from export modules to be managed here)
resource "google_service_account" "collector_sa" {
  account_id   = "pmp-collector-sa"
  display_name = "PMP Cloud Run Collector"
}

resource "google_service_account" "pubsub_push_sa" {
  account_id   = "pmp-pubsub-push-sa"
  display_name = "PMP Pub/Sub Push SA"
}

resource "google_service_account" "scheduler_sa" {
  account_id   = "pmp-scheduler-sa"
  display_name = "PMP Cloud Scheduler SA"
}

# Create Station Info Writer Service Account
resource "google_service_account" "station_info_writer_sa" {
  account_id   = "pmp-station-info-writer-sa"
  display_name = "Station Info Writer Service Account"
}

# Collector SA: Pub/Sub Publisher on station_info topic
resource "google_pubsub_topic_iam_member" "collector_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.station_info_topic.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.collector_sa.email}"
}

# Writer SA: Dataset-level permissions (Hardened)
resource "google_bigquery_dataset_iam_member" "writer_curated_editor" {
  dataset_id = google_bigquery_dataset.pmp_curated.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.station_info_writer_sa.email}"
}

# Dataflow SA: Dataset-level permissions for DLQ table (pmp_ops)
# Note: Dataflow SA already has project-level bigquery.dataEditor
# Adding dataset-specific permissions for clarity and least-privilege
resource "google_bigquery_dataset_iam_member" "dataflow_sa_pmp_ops_dataeditor" {
  dataset_id = google_bigquery_dataset.pmp_ops.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "dataflow_sa_pmp_ops_metadataviewer" {
  dataset_id = google_bigquery_dataset.pmp_ops.dataset_id
  role       = "roles/bigquery.metadataViewer"
  member     = "serviceAccount:${google_service_account.dataflow_sa.email}"
}


# Push SA: Cloud Run Invoker on Writer service
resource "google_cloud_run_v2_service_iam_member" "push_sa_invoke_writer" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.station_info_writer.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_push_sa.email}"
}

# Scheduler SA: Cloud Run Invoker on Collector service
resource "google_cloud_run_v2_service_iam_member" "scheduler_sa_invoke_collector" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.station_info_collector.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# Push SA: Cloud Run Invoker on BQ Writer service
resource "google_cloud_run_v2_service_iam_member" "push_sa_invoke_bq_writer" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pmp_bq_writer.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_push_sa.email}"
}

# Scheduler SA: Cloud Run Invoker on Velib Collector service
resource "google_cloud_run_v2_service_iam_member" "scheduler_sa_invoke_velib_collector" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pmp_velib_collector.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
}



# Pub/Sub Push SA: Dataset-level permissions (Hardened for pmp-bq-writer)
resource "google_bigquery_dataset_iam_member" "push_sa_raw_editor" {
  dataset_id = google_bigquery_dataset.pmp_raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pubsub_push_sa.email}"
}

resource "google_service_account_iam_member" "scheduler_agent_token_creator" {
  service_account_id = google_service_account.scheduler_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

resource "google_pubsub_topic_iam_member" "collector_publisher_events" {
  project = var.project_id
  topic   = google_pubsub_topic.pmp_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.collector_sa.email}"
}

# ========================
# IDFM Disruption Pipeline Service Account
# ========================
resource "google_service_account" "idfm_collector_sa" {
  account_id   = "pmp-idfm-collector-sa"
  display_name = "IDFM Disruption Collector SA"
}

# IDFM Collector: BigQuery DataEditor on pmp_raw
resource "google_bigquery_dataset_iam_member" "idfm_collector_bq_raw" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.pmp_raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.idfm_collector_sa.email}"
}

# IDFM Collector: Access Secret Manager (API Key)
resource "google_secret_manager_secret_iam_member" "idfm_collector_secret_access" {
  secret_id = google_secret_manager_secret.idfm_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.idfm_collector_sa.email}"
}

# Scheduler: Invoke IDFM Collector Cloud Run Service
resource "google_cloud_run_v2_service_iam_member" "scheduler_invoke_idfm" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pmp_idfm_collector.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# ========================
# dbt Runner Service Account
# ========================
resource "google_service_account" "dbt_runner_sa" {
  account_id   = "pmp-dbt-runner-sa"
  display_name = "dbt Runner Service Account"
}

# dbt Runner: Read from pmp_raw (source tables)
resource "google_bigquery_dataset_iam_member" "dbt_runner_raw_viewer" {
  dataset_id = google_bigquery_dataset.pmp_raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dbt_runner_sa.email}"
}

# dbt Runner: Write to pmp_dbt_dev_curated (target tables)
# Project-level because dbt-managed datasets aren't in Terraform
resource "google_project_iam_member" "dbt_runner_bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dbt_runner_sa.email}"
}

resource "google_project_iam_member" "dbt_runner_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt_runner_sa.email}"
}

# Scheduler: Invoke dbt Runner Cloud Run Job
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoke_dbt" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.dbt_runner.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
}
