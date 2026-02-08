# File: docs/00-bootstrap.md

# Bootstrap & Prerequisites

## 1. Prerequisites
- **Google Cloud Project** created (e.g., `my-mobility-project`). 
- **Project ID**: You MUST use your own unique Project ID. Do NOT use `paris-mobility-pulse`.
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
# Edit .env and set your PROJECT_ID (NOT paris-mobility-pulse)
nano .env  
```

> [!CAUTION]
> **Do not use the string `paris-mobility-pulse` as your Project ID.** 
> This is a global identifier; you must use the ID of the GCP project you just created.

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

### 4. (Optional) Adopt Existing Production Data
**If you are deploying to an existing project with live data:**
Do NOT run `make clean-cloud`. Instead, adopt the existing resources into Terraform:
```bash
make adopt-prod
```
This safely imports your BigQuery tables, Topics, and Storage buckets so Terraform manages them without deletion.

### 5. Deploy Infrastructure
Once bootstrapped (and optionally adopted), deploy the full stack:
```bash
make deploy
```

## 6. Verification
If the bootstrap completes successfully, you are ready to deploy:

```bash
make deploy
```

> [!TIP]
> **Troubleshooting: Permission Denied**
> If you encounter a `Permission denied` error when running make commands (e.g., related to `check_env.sh`), simply make the scripts executable:
> ```bash
> chmod +x scripts/*.sh scripts/setup/*.sh
> ```
> [!TIP]
> **Troubleshooting: Cloud Shell Timeout / Metadata Error**
> If `make deploy` fails with `Compute Engine Metadata server unavailable` or `TypeError: string indices must be integers`, your Cloud Shell session has disconnected from its identity server.
>
> **Fix:**
> 1. Run `gcloud auth login --update-adc` inside Cloud Shell.
> 2. If that hangs, close the tab and open a new Cloud Shell instance.

## 5. Security & Safety Note
You might wonder: *If I run this, can it accidentally modify someone else's project?*

**No. It is completely safe.**

1.  **Authentication Required**: The script uses your local credentials (`gcloud auth login`). It cannot access any project you don't own.
2.  **Local-Only Cleanup**: The `rm terraform.tfstate` command in `bootstrap.sh` only deletes a **local text file** on your machine to ensure a clean install. It sends no delete commands to Google Cloud.
3.  **Project Isolation**: If you accidentally set someone else's Project ID in `.env`, the script will simply fail with a `Permission Denied` error because you are not an Owner of that project.

## 5. Teardown & Reset (Clean Cleanup)
If you want to **stop everything** to save money, or if you need to **reset the environment** to test the bootstrap process from scratch (e.g., for judging reproducibility):

```bash
make clean-cloud
```

**⚠️ WARNING: DELETES DATA**
This command explicitly deletes all project resources including:
-   BigQuery Datasets (`pmp_raw`, `pmp_marts`, etc.)
-   Pub/Sub Topics & Subscriptions
-   Cloud Run Services & Scheduler Jobs
-   Service Accounts

Use this when you want a completely fresh start.

## 6. Daily Operations FAQ

### Can I just use `make demo-up`?
Yes, **IF** you have already deployed the infrastructure.
-   **`make deploy`**: The "Construction Crew" (Builds servers, databases, permissions).
-   **`make demo-up`**: The "Remote Control" (Turns the existing machines ON/OFF).

If you haven't deployed, `make demo-up` will fail because the resources don't exist.

### I get "Resource Already Exists" errors on a new deploy?
This usually means you deleted your local state file, but the cloud resources are still active.

**Fix:** Run `make clean-cloud` (see Section 5) to reset the cloud environment, then run `make bootstrap` and `make deploy` again.
