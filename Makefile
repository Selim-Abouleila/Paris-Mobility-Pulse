.PHONY: fmt check lint install test typecheck

# Load .env variables if file exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Default target
all: check

# --------------------------
# Golden Path (Start Here)
# --------------------------

# 1. Setup project (Enable APIs, Init Terraform)
bootstrap:
	@chmod +x scripts/setup/check_env.sh scripts/setup/bootstrap.sh || true
	@./scripts/setup/bootstrap.sh

# 2. Deploy Infrastructure (Terraform + dbt)
deploy:
	@./scripts/setup/check_env.sh
	@echo "==> installing dependencies..."
	@pip install -r requirements.txt
	@echo "==> Building Containers..."
	@chmod +x scripts/setup/build.sh
	@./scripts/setup/build.sh
	@echo "==> Deploying Infrastructure..."
	@terraform -chdir=infra/terraform init -upgrade -reconfigure \
		-backend-config="bucket=pmp-terraform-state-$(PROJECT_ID)"
	@terraform -chdir=infra/terraform apply -var-file="terraform.tfvars" \
		-var="project_id=$(PROJECT_ID)" -auto-approve
	@echo "==> Deploying Analytics (dbt)..."
	@echo "    Detecting BigQuery location..."
	$(eval DBT_LOCATION := $(shell bq show --format=prettyjson $(PROJECT_ID):pmp_curated 2>/dev/null | grep '"location":' | cut -d '"' -f 4 || echo "EU"))
	@echo "    Location detected: $(DBT_LOCATION)"
	@export DBT_LOCATION=$(DBT_LOCATION) && dbt deps --project-dir dbt --profiles-dir dbt
	@export DBT_LOCATION=$(DBT_LOCATION) && dbt run --project-dir dbt --profiles-dir dbt
	@export DBT_LOCATION=$(DBT_LOCATION) && dbt test --project-dir dbt --profiles-dir dbt

# 3. Start Demo (Resume schedulers, start streaming)
demo-up:
	@./scripts/setup/check_env.sh
	@./scripts/pmpctl.sh up

# 4. Stop Demo (Pause schedulers, cancel streaming)
demo-down:
	@./scripts/pmpctl.sh down

# 5. Emergency Cleanup (Fix "Already Exists" errors)
clean-cloud:
	@chmod +x scripts/setup/clean_project.sh
	@./scripts/setup/clean_project.sh

# 6. Adopt Production Resources (Import existing without deleting)
adopt-prod:
	@chmod +x scripts/adopt_prod.sh
	@./scripts/adopt_prod.sh

# --------------------------
# Dev / CI
# --------------------------

# Install development dependencies
install:
	pip install ruff mypy pytest types-requests types-flask

# Format code
fmt:
	ruff format .
	terraform fmt -recursive infra

# Check formatting and linting
check:
	ruff format --check .
	ruff check .
	mypy .
	pytest -q
	terraform fmt -check -recursive infra

# Lint Python code only
lint:
	ruff check .

# Run type checks
typecheck:
	mypy .

# Run tests
test:
	pytest -v
