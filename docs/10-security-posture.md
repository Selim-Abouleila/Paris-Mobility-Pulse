# Security Posture: Paris Mobility Pulse (PMP)

This document outlines the security architecture, principles, and controls implemented for the Paris Mobility Pulse data platform. It serves as the primary reference for identity management, access boundaries, and infrastructure hardening.

## 1. Security Goals & Assumptions

### Principles
-   **Least Privilege Identity**: Every component (Cloud Run, Dataflow, Scheduler) runs as a dedicated Service Account with the minimum required permissions.
-   **Zero Trust Networking**: All Cloud Run services are private by default. Invocations are authenticated via OIDC tokens.
-   **Data Boundary Isolation**: BigQuery datasets are segmented by layer (Raw, Curated, Marts, Ops) with distinct access controls.
-   **Configuration as Code**: all security policies (IAM, Firewalls) are defined in Terraform. No manual console changes.

### Assumptions
-   **Public Data**: The source data (Vélib availability) is public Opendata. Confidentiality concerns are primarily for **infrastructure integrity, billing protection, and operational continuity**, not user privacy.
-   **Demo Environment**: While "production-grade", the pipeline is designed for cost-efficiency. Highly expensive controls (e.g., VPC Service Controls, Cloud HSM) are out of scope for this MVP but the architecture supports future adoption.

---

## 2. Identity & Access Management (IAM)

We use **dedicated Service Accounts (SAs)** for each compute workload to prevent lateral movement.

| Service Account | Component | Role / Justification | Access Scope |
| :--- | :--- | :--- | :--- |
| `pmp-collector-sa` | Cloud Run Collector | `pubsub.publisher` | Publish to `pmp-events` & `pmp-velib-station-info` ONLY. |
| `pmp-station-info-writer-sa` | Cloud Run Writer | `bigquery.dataEditor` | Write to `pmp_curated.velib_station_information`. |
| `pmp-bq-writer-sa` | Cloud Run Writer | `bigquery.dataEditor` | Write to `pmp_raw` datasets. |
| `pmp-dataflow-sa` | Dataflow Worker | `dataflow.worker`<br>`bigquery.dataEditor`<br>`pubsub.subscriber` | Read `pmp-events`, Write `pmp_curated`, Write `pmp_ops` (DLQ). |
| `pmp-scheduler-sa` | Cloud Scheduler | `run.invoker` | Invoke Collector services via OIDC. |
| `pmp-pubsub-push-sa` | Pub/Sub Push | `run.invoker` | Invoke Writer services via OIDC. |
| `pmp-dlq-replayer-sa` | Cloud Run Job | `pubsub.writer`<br>`pubsub.subscriber` | Consume DLQ subscription, Republish to source topic. |

---

## 3. Cloud Run Exposure

All Cloud Run services are **Private (No Allow Unauthenticated)** by default.

### Invocation Path
1.  **Scheduler → Collector**:
    -   Cloud Scheduler uses `pmp-scheduler-sa`.
    -   Authenticates via OIDC ID token.
    -   `pmp-velib-collector` accepts only this identity.

2.  **Pub/Sub → Writer**:
    -   Pub/Sub Push Subscription uses `pmp-pubsub-push-sa`.
    -   Authenticates via OIDC ID token.
    -   `pmp-bq-writer` accepts only this identity.

**Strict Enforcement**: `roles/run.invoker` is bound **only** to the specific SA required for invocation. `allUsers` is strictly forbidden.

---

## 4. Pub/Sub Permission Model

We separate the "Producer" and "Consumer" roles to establish a clear data flow.

| Topic | Publisher (Producer) | Subscriber (Consumer) | Replay/Audit |
| :--- | :--- | :--- | :--- |
| `pmp-events` | `pmp-collector-sa` | `pmp-dataflow-sa`<br>`pmp-pubsub-push-sa` (MVP) | `pmp-events-sub` (Debug) |
| `pmp-velib-station-info` | `pmp-collector-sa` | `pmp-pubsub-push-sa` | `pmp-dlq-replayer-sa` (on retry) |
| `pmp-*-dlq` | Cloud Pub/Sub Service Agent<br>Dataflow Worker | `pmp-dlq-replayer-sa` | `pmp-ops` (BigQuery) |

---

## 5. BigQuery Data Boundaries

Datasets are logically isolated. We are migrating away from Project-Level roles to Dataset-Level roles.

| Layer | Dataset | Write Access | Read Access | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Raw** | `pmp_raw` | `pmp-bq-writer-sa` | `group:data-engineers` | Landing zone for original JSON. Immutable. |
| **Curated** | `pmp_curated` | `pmp-dataflow-sa` | `group:data-analysts` | Cleaned, deduplicated, schema-validated tables. |
| **Marts** | `pmp_marts` | *Read-Only Views* | `service:looker-studio` | Aggregated business views for dashboards. |
| **Ops** | `pmp_ops` | `pubsub-service-agent`<br>`pmp-dataflow-sa` | `group:platform-admins` | Dead Letter Queues and Pipeline Audit logs. |

---

## 6. Secrets Management

**Current State**: No sensitive secrets (passwords/keys) are strictly required for the public data MVP.
**Future State (Ready)**: If API keys or database credentials are added:
1.  **Storage**: Google Secret Manager (GSM).
2.  **Access**: `roles/secretmanager.secretAccessor` granted ONLY to the runtime SA.
3.  **Consumption**: Mounted as environment variables or volumes in Cloud Run.
4.  **Anti-Pattern**: NEVER store secrets in `terraform.tfvars` or environment variables in code.

---

## 7. Security Controls & Hardening

### Infrastructure
-   **Uniform Bucket Level Access**: Enforced on all GCS buckets (Dataflow templates, Terraform state).
-   **Encryption**: Google-managed keys (default) are sufficient for public data.
-   **Logging**: Cloud Logging enabled for all components.

### Software Supply Chain
-   **Container Images**: Built via Cloud Build or GitHub Actions.
-   **Immutability**: Cloud Run tags are used to promote specific revisions (e.g., `latest` for dev, specific SHA for prod).

---

## 8. Verification & Audit

### Verify Cloud Run is Private
```bash
# Should return 401 Unauthorized or 403 Forbidden
curl -X GET $(gcloud run services describe pmp-velib-collector --region europe-west9 --format 'value(status.url)')
```

### Verify Service Account Identity
```bash
# Check who allows Scheduler to invoke Collector
gcloud run services get-iam-policy pmp-velib-collector \
  --region europe-west9 \
  --flatten="bindings[].members" \
  --format="table(bindings.role, bindings.members)" \
  --filter="bindings.role:roles/run.invoker"
```

### Verify BigQuery Access
```bash
# List permissions on the Curated dataset
bq show --format=prettyjson pmp_curated | jq '.access'
```
