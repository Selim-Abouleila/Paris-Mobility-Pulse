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

resource "google_project_iam_member" "bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
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
data "google_service_account" "collector_sa" {
  account_id = "pmp-collector-sa"
}

data "google_service_account" "pubsub_push_sa" {
  account_id = "pmp-pubsub-push-sa"
}

data "google_service_account" "scheduler_sa" {
  account_id = "pmp-scheduler-sa"
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
  member  = "serviceAccount:${data.google_service_account.collector_sa.email}"
}

# Writer SA: BigQuery Data Editor (project-level, consistent with existing pattern)
resource "google_project_iam_member" "writer_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.station_info_writer_sa.email}"
}

# Push SA: Cloud Run Invoker on Writer service
resource "google_cloud_run_v2_service_iam_member" "push_sa_invoke_writer" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.station_info_writer.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${data.google_service_account.pubsub_push_sa.email}"
}

# Scheduler SA: Cloud Run Invoker on Collector service
resource "google_cloud_run_v2_service_iam_member" "scheduler_sa_invoke_collector" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.station_info_collector.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${data.google_service_account.scheduler_sa.email}"
}

# Cloud Scheduler Service Agent: Token Creator for Scheduler SA
resource "google_service_account_iam_member" "scheduler_agent_token_creator" {
  service_account_id = data.google_service_account.scheduler_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}
