.PHONY: fmt check lint install

# Default target
all: check

# Install development dependencies
install:
	pip install ruff

# Format code
fmt:
	ruff format .
	terraform fmt -recursive infra

# Check formatting and linting
check:
	ruff format --check .
	ruff check .
	terraform fmt -check -recursive infra

# Lint Python code only
lint:
	ruff check .
