# File: docs/00-bootstrap.md

# Bootstrap & Prerequisites

## 1. Prerequisites
- **Google Cloud Project** created (ID: `paris-mobility-pulse` or your own).
- **Billing enabled** for the project.
- **Local Tools**:
    - `gcloud` (Authenticated)
    - `terraform` (v1.5+)
    - `python3`
    - `make`

## 2. Configuration
Copy the example configuration and set your project details:

```bash
cp .env.example .env
nano .env  # Set PROJECT_ID=...
```

## 3. Automated Bootstrap
Instead of manually clicking buttons in the console, run:

```bash
make bootstrap
```

This script (`scripts/setup/bootstrap.sh`) will automatically:
1.  **Validate** your environment tools and `.env` config.
2.  **Enable** the Service Usage API (required to enable other APIs).
3.  **Enable** all other required GCP APIs (Cloud Run, Pub/Sub, BigQuery, etc.).
4.  **Generate** `infra/terraform/terraform.tfvars` from your configuration.
5.  **Initialize** Terraform (`terraform init`).

## 4. Verification
If the bootstrap completes successfully, you are ready to deploy:

```bash
make deploy
```
