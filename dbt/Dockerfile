FROM python:3.11-slim

WORKDIR /app

# Install dbt-bigquery
RUN pip install --no-cache-dir dbt-bigquery==1.11.0

# Copy dbt project
COPY dbt/ /app/dbt/

# Default: run only incremental curated models
CMD ["dbt", "run", "--project-dir", "/app/dbt", "--profiles-dir", "/app/dbt", "--select", "curated"]
