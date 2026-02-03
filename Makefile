.PHONY: fmt check lint install test typecheck

# Default target
all: check

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
