.PHONY: fmt check lint install test typecheck

# Default target
all: check

# --------------------------
# Golden Path (Start Here)
# --------------------------

# 1. Setup project (Enable APIs, Init Terraform)
bootstrap:
	@chmod +x scripts/setup/check_env.sh scripts/setup/bootstrap.sh || true
	@./scripts/setup/bootstrap.sh

# 2. Deploy Infrastructure (Terraform)
deploy:
	@./scripts/setup/check_env.sh
	@echo "==> Building Containers..."
	@chmod +x scripts/setup/build.sh
	@./scripts/setup/build.sh
	@echo "==> Deploying Infrastructure..."
	@terraform -chdir=infra/terraform apply -var-file="terraform.tfvars" -auto-approve

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
