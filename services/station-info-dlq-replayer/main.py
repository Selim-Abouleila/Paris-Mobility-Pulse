import os
import time
import uuid
import json
import logging
from datetime import datetime, timezone

from google.cloud import pubsub_v1
from google.api_core import exceptions

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

PROJECT_ID = os.getenv("PROJECT_ID", "paris-mobility-pulse")
DLQ_SUB = os.getenv(
    "DLQ_SUB",
    f"projects/{PROJECT_ID}/subscriptions/pmp-velib-station-info-push-dlq-hold-sub",
)
DEST_TOPIC = os.getenv(
    "DEST_TOPIC",
    f"projects/{PROJECT_ID}/topics/pmp-velib-station-info",
)

MAX_MESSAGES = int(os.getenv("MAX_MESSAGES", "50"))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "10"))

QPS = float(os.getenv("QPS", "5"))
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"
ACK_SKIPPED = os.getenv("ACK_SKIPPED", "false").lower() == "true"

PULL_TIMEOUT_S = float(os.getenv("PULL_TIMEOUT_S", "10"))
PUBLISH_TIMEOUT_S = float(os.getenv("PUBLISH_TIMEOUT_S", "30"))

# Pub/Sub modifyAckDeadline max is 600s.
MAX_ACK_DEADLINE_S = 600
ACK_DEADLINE_BUFFER_S = 60  # extra safety margin


def _now_rfc3339() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _sleep_interval(qps: float) -> float:
    # QPS <= 0 means "no throttling"
    if qps <= 0:
        return 0.0
    return 1.0 / qps


def _compute_ack_deadline(batch_size: int, sleep_s: float) -> int:
    """
    Estimate worst-case time until the *last* message in the batch gets acked.
    We ack each message after publishing, but messages later in the batch wait.
    """
    # Worst-case wait before processing last msg = (batch_size-1)*sleep_s
    estimated_processing_s = int(
        (max(0, batch_size - 1) * sleep_s) + ACK_DEADLINE_BUFFER_S
    )

    # Clamp to Pub/Sub max per request.
    return min(MAX_ACK_DEADLINE_S, max(10, estimated_processing_s))


def replay_dlq() -> int:
    subscriber = pubsub_v1.SubscriberClient()
    publisher = pubsub_v1.PublisherClient()

    run_id = str(uuid.uuid4())
    sleep_s = _sleep_interval(QPS)

    logger.info("Starting DLQ Replay Run: %s", run_id)
    logger.info("Source Sub: %s", DLQ_SUB)
    logger.info("Dest Topic: %s", DEST_TOPIC)
    logger.info(
        "Config: MAX_MESSAGES=%s BATCH_SIZE=%s QPS=%s DRY_RUN=%s ACK_SKIPPED=%s",
        MAX_MESSAGES,
        BATCH_SIZE,
        QPS,
        DRY_RUN,
        ACK_SKIPPED,
    )

    stats = {"pulled": 0, "republished": 0, "acked": 0, "skipped": 0, "failed": 0}

    while stats["pulled"] < MAX_MESSAGES:
        remaining = MAX_MESSAGES - stats["pulled"]
        batch_size = max(1, min(BATCH_SIZE, remaining))

        # If QPS is extremely low, batch processing might exceed 600s max ack deadline.
        # In that case, shrink the batch.
        if sleep_s > 0:
            max_batch_that_fits = (
                int((MAX_ACK_DEADLINE_S - ACK_DEADLINE_BUFFER_S) / sleep_s) + 1
            )
            if max_batch_that_fits < 1:
                max_batch_that_fits = 1
            if batch_size > max_batch_that_fits:
                logger.warning(
                    "BATCH_SIZE=%s too large for QPS=%s (ack deadline max %ss). "
                    "Reducing batch_size to %s.",
                    batch_size,
                    QPS,
                    MAX_ACK_DEADLINE_S,
                    max_batch_that_fits,
                )
                batch_size = max_batch_that_fits

        try:
            response = subscriber.pull(
                request={"subscription": DLQ_SUB, "max_messages": batch_size},
                timeout=PULL_TIMEOUT_S,
            )
        except exceptions.DeadlineExceeded:
            logger.info("Pull timeout: no messages available right now.")
            break
        except Exception as e:
            logger.error("Error pulling messages: %s", e)
            break

        if not response.received_messages:
            logger.info("No more messages received.")
            break

        # Extend ack deadline for the batch to avoid expiry while we rate-limit.
        ack_ids = [rm.ack_id for rm in response.received_messages]
        ack_deadline_s = _compute_ack_deadline(len(ack_ids), sleep_s)
        try:
            subscriber.modify_ack_deadline(
                request={
                    "subscription": DLQ_SUB,
                    "ack_ids": ack_ids,
                    "ack_deadline_seconds": ack_deadline_s,
                }
            )
        except Exception as e:
            # Not fatal: we can still try, but duplicates become more likely.
            logger.warning("Failed to extend ack deadline: %s", e)

        for rm in response.received_messages:
            stats["pulled"] += 1
            msg = rm.message
            attributes = dict(msg.attributes or {})

            # Loop guard: treat any truthy replay marker as already replayed.
            if str(attributes.get("replay", "")).lower() == "true":
                logger.info(
                    "Skipping message %s (already replay=true).", msg.message_id
                )
                stats["skipped"] += 1
                if ACK_SKIPPED and not DRY_RUN:
                    try:
                        subscriber.acknowledge(
                            request={"subscription": DLQ_SUB, "ack_ids": [rm.ack_id]}
                        )
                        stats["acked"] += 1
                    except Exception as e:
                        logger.error(
                            "Failed to ack skipped message %s: %s", msg.message_id, e
                        )
                continue

            # Remove DLQ metadata + drill flags
            clean_attributes = {
                k: v
                for k, v in attributes.items()
                if not k.startswith("CloudPubSubDeadLetter")
            }
            clean_attributes.pop(
                "dl_test", None
            )  # Corrected to match earlier logic but user used dlq_test. Actually user prompt said dlq_test.

            # Add replay metadata
            clean_attributes["replay"] = "true"
            clean_attributes["replay_id"] = run_id
            clean_attributes["replay_source"] = DLQ_SUB.split("/")[-1]

            # Ensure all values are strings (Pub/Sub requirement).
            clean_attributes = {str(k): str(v) for k, v in clean_attributes.items()}

            if DRY_RUN:
                logger.info(
                    "[DRY RUN] Would republish message %s -> %s attrs=%s",
                    msg.message_id,
                    DEST_TOPIC,
                    clean_attributes,
                )
                stats["republished"] += 1
                # No ack in dry-run
                continue

            try:
                future = publisher.publish(
                    DEST_TOPIC, data=msg.data, **clean_attributes
                )
                new_msg_id = future.result(timeout=PUBLISH_TIMEOUT_S)
                stats["republished"] += 1
                logger.info("Republished %s -> %s", msg.message_id, new_msg_id)

                subscriber.acknowledge(
                    request={"subscription": DLQ_SUB, "ack_ids": [rm.ack_id]}
                )
                stats["acked"] += 1

                if sleep_s > 0:
                    time.sleep(sleep_s)

            except Exception as e:
                logger.error("Failed to process message %s: %s", msg.message_id, e)
                stats["failed"] += 1
                # Do NOT ack on failure (so it can be retried later)

    logger.info("Replay Summary:\n%s", json.dumps(stats, indent=2))
    print(f"Summary: {stats}")

    # Exit code: non-zero if failures occurred (useful for Cloud Run Job observability)
    return 0 if stats["failed"] == 0 else 2


if __name__ == "__main__":
    raise SystemExit(replay_dlq())
