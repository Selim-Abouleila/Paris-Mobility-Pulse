# Security Implementation Plan

> **Note**: This plan describes the necessary Terraform refactoring to fully enforce the security posture defined in `docs/10-security-posture.md`. All changes are "Least Privilege" hardening measures.

## 1. Split Broad Role Assignments
**File**: `infra/terraform/iam.tf`

Currently, SAs like `pmp-station-info-writer-sa` and `pmp-dataflow-sa` often have `roles/bigquery.dataEditor` at the **Project Level**. This allows them to write to *any* dataset.

**Action**:
- Remove `google_project_iam_member` resources for `roles/bigquery.dataEditor`.
- Replace with `google_bigquery_dataset_iam_member` resources scoped to specific datasets.

**Example Change**:
```hcl
# REMOVE THIS
# resource "google_project_iam_member" "writer_bq_editor" { ... }

# ADD THIS
resource "google_bigquery_dataset_iam_member" "writer_raw_editor" {
  dataset_id = google_bigquery_dataset.pmp_raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pmp_bq_writer_sa.email}"
}
```

## 2. Enforce Logical Service Account Separation
**File**: `infra/terraform/iam.tf`

Ensure every Cloud Run service has a unique SA. Currently:
- `pmp-velib-collector` uses `collector_sa`
- `pmp-velib-station-info-collector` uses `collector_sa` (Reuse!)

**Action**:
- Create `station_info_collector_sa` for the Station Info collector.
- Grant `pubsub.publisher` *specifically* for the `pmp-velib-station-info` topic to this new SA.
- Update `infra/terraform/cloud_run_station_info.tf` to use the new SA.

## 3. Harden Cloud Run Invocations
**File**: `infra/terraform/cloud_run_*.tf`

Verify `ingress` settings.
- **Collectors**: Should be `INGRESS_TRAFFIC_ALL` (to allow Scheduler/Internet invocation if needed) OR `INGRESS_TRAFFIC_INTERNAL_ONLY` if triggered via private Scheduler/PubSub. Since we use OIDC, `INGRESS_TRAFFIC_ALL` is acceptable IF IAM is strict.
- **Writers**: Should be `INGRESS_TRAFFIC_INTERNAL_ONLY` (triggered by Pub/Sub Push).

**Action**:
- Explicitly set `ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"` for all writers in `cloud_run_station_info.tf` and `cloud_run_bq.tf`.

## 4. Pub/Sub Subscription Permissions
**File**: `infra/terraform/pubsub.tf` & `iam.tf`

Explicitly map Publisher/Subscriber roles.
- Ensure `pmp-pubsub-push-sa` does NOT have `pubsub.publisher`. It only needs to invoke Cloud Run.
- Ensure `pmp-collector-sa` does NOT have `pubsub.subscriber`. It only needs to publish.

## 5. Secret Manager Foundation (Optional/Future)
**File**: `infra/terraform/secrets.tf` (New)

Create a placeholder structure for secrets management if future credentials are required.

```hcl
resource "google_secret_manager_secret" "api_key" {
  secret_id = "pmp-api-key"
  replication {
    automatic = true
  }
}

# Grant Access
resource "google_secret_manager_secret_iam_member" "collector_access" {
  secret_id = google_secret_manager_secret.api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.collector_sa.email}"
}
```

## 6. GCS Uniform Bucket Access
**File**: `infra/terraform/storage.tf`

Enforce uniform access on the Dataflow bucket.

```hcl
resource "google_storage_bucket" "dataflow_bucket" {
  # ... existing config ...
  uniform_bucket_level_access = true
}
```
