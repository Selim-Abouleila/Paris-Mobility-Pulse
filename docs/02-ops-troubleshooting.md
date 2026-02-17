# Operations & Incident Response Manual

This document serves as the **SRE Runbook** for the Paris Mobility Pulse pipeline. It maps out standard operating procedures, incident response workflows, and log signatures for rapid debugging.

> [!NOTE]
> **Scope**: This runbook covers the **core MVP pipeline** — Cloud Scheduler → Cloud Run Collector → Pub/Sub → Cloud Run Writer → BigQuery (`pmp_raw`), plus Dataflow streaming curation to `pmp_curated`. For component-specific troubleshooting, see:
> - [04 - Dataflow Curation](04-dataflow-curation.md) — Dataflow job issues, DLQ table queries
> - [09 - Reliability: DLQ + Replay](09-reliability-dlq-replay.md) — DLQ inspection and replay procedures
> - [07 - Operations: Demo Control](07-operations-demo-control.md) — Start/stop lifecycle via `pmpctl.sh`

## 1. System Health Checks

Use these commands to quickly assess the pulse of the system.

### A. The "Pulse" Dashboard
Run this one-liner to get a snapshot of all critical components:

```bash
# Check Scheduler (Ingestion), Cloud Run (Processing), and Dataflow (Streaming)
echo "--- SCHEDULER ---" && \
gcloud scheduler jobs list --location=europe-west1 --project=paris-mobility-pulse && \
echo -e "\n--- CLOUD RUN ---" && \
gcloud run services list --region=europe-west9 --project=paris-mobility-pulse && \
echo -e "\n--- DATAFLOW ---" && \
gcloud dataflow jobs list --region=europe-west9 --filter="state=Running" --project=paris-mobility-pulse
```

**Healthy Output Indicators**:
*   **Scheduler**: State `ENABLED` (if active) or `PAUSED` (if demo mode is off).
*   **Cloud Run**: Status `OK`, latest revision is active.
*   **Dataflow**: One job in `Running` state (Type: Streaming).

### B. End-to-End Latency Probe
Check the timestamp of the most recent row in BigQuery to verify data freshness:

```sql
SELECT 
  MAX(ingest_ts) as last_ingest,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingest_ts), MINUTE) as latency_min
FROM `paris-mobility-pulse.pmp_curated.velib_station_status`
```
*   **Target**: `latency_min < 5` (Dataflow buffering + Windowing may add slight delay).

---

## 2. Incident Response (Decision Trees)

Follow these workflows when alerts fire or anomalies are detected.

### Scenario A: "Data is Stale" (High Latency)
**Trigger**: Dashboard shows flat lines or BigQuery latency > 15 mins.

1.  **Check Ingestion**: Is the Scheduler running?
    *   *No*: `gcloud scheduler jobs resume ...`
    *   *Yes*: Check Collector logs for HTTP 200s.
2.  **Check Pub/Sub**: Is the backlog growing?
    *   *Command*: `gcloud pubsub subscriptions describe pmp-events-dataflow-sub`
    *   *If Backlog > 1000*: Dataflow is likely stuck or failing.
3.  **Check Dataflow**: Is the job active?
    *   *If Failed*: Check logs for "OutOfMemory" or "Permissions".
    *   *Action*: Drain/Cancel job and redeploy using `./scripts/pmpctl.sh up`.

### Scenario B: "Cost Spike Alert"
**Trigger**: Budget alert email (e.g., "50% of budget consumed").

1.  **Emergency Stop**: Immediately stop all cost drivers.
    ```bash
    ./scripts/pmpctl.sh down
    ```
2.  **Identify Leak**:
    *   **Dataflow**: Was a job left running overnight? (Cost: ~$0.05/hour/worker).
    *   **Cloud Run**: Is there a retry storm causing infinite requests? (See *Log Signatures* below).

---

## 3. Log Analysis & Signatures

Recognize healthy vs. unhealthy behavior in Cloud Logging.

### ✅ Healthy Ingestion (Collector)
**Signature**: HTTP 200 OK + JSON Payload size > 0.

```json
{
  "httpRequest": {
    "status": 200,
    "requestUrl": "https://pmp-velib-collector-.../collect"
  },
  "textPayload": "Published 1 messages to pmp-events",
  "severity": "INFO"
}
```

### ❌ Retry Storm (The "Infinite Loop")
**Signature**: HTTP 500s or 429s appearing every few seconds. This is dangerous for costs.
**Action**: **PAUSE SCHEDULER IMMEDIATELY**.

```json
{
  "severity": "ERROR",
  "textPayload": "500 Internal Server Error: Push endpoint failed...",
  "httpRequest": {
    "status": 500
  }
}
```

---

## 4. Known Failure Modes library

| ID | Symptom | Root Cause | Fix |
| :--- | :--- | :--- | :--- |
| **ERR-01** | `401 Anonymous caller` in logs/CLI | ADC Token expired. | `gcloud auth login --update-adc` |
| **ERR-02** | BigQuery `COUNT(*)` flatlining | Aggressively cached query results. | Add `--nouse_cache` to your `bq query` command. |
| **ERR-03** | Dataflow Job "Stuck" at 0 workers | Quota exceeded or permission issue. | Check Compute Engine quotas in region `europe-west9`. |
| **ERR-04** | `Field value cannot be empty` | Schema mismatch (e.g. missing `event_ts`). | Fix Cloud Run Writer normalization logic. |

---

## 5. Operations Reference

### Control Plane
All routine operations should use the control script to ensure safe state transitions.

*   **Start Demo**: `./scripts/pmpctl.sh up`
*   **Stop Demo**: `./scripts/pmpctl.sh down`
*   **Status**: `./scripts/pmpctl.sh status`

See [07 - Operations: Demo Control](07-operations-demo-control.md) for the full CLI documentation.
