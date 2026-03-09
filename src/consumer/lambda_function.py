"""Consumer Lambda function for the Library Book Request System.

This Lambda function processes book request messages from an SQS queue,
enriches the data with a request timestamp and initial review status,
and stores the item in DynamoDB.

Error handling features:
- Exponential backoff with jitter for transient DynamoDB errors
- Contextual logging for all errors
- Batch item failure reporting for partial batch response (DLQ routing)
- Timeout handling for API/DynamoDB operations
"""

import json
import logging
import os
import random
import time
from datetime import datetime, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError, ConnectTimeoutError, ReadTimeoutError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Retry configuration
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "3"))
BASE_DELAY_SECONDS = float(os.environ.get("BASE_DELAY_SECONDS", "0.1"))
MAX_DELAY_SECONDS = float(os.environ.get("MAX_DELAY_SECONDS", "2.0"))

# Transient DynamoDB error codes that are safe to retry
RETRYABLE_ERROR_CODES = frozenset({
    "ProvisionedThroughputExceededException",
    "ThrottlingException",
    "InternalServerError",
    "ServiceUnavailable",
    "RequestLimitExceeded",
})

# boto3 client configuration with connect and read timeouts
BOTO3_CONFIG = Config(
    connect_timeout=5,
    read_timeout=10,
    retries={"max_attempts": 0},  # We handle retries ourselves
)


def _get_table_name():
    """Get the DynamoDB table name from environment variables."""
    return os.environ.get("DYNAMODB_TABLE_NAME", "")


def calculate_backoff(attempt, base_delay=None, max_delay=None):
    """Calculate exponential backoff delay with full jitter.

    Uses the "Full Jitter" algorithm: sleep = random_between(0, min(cap, base * 2^attempt))

    Args:
        attempt: The current retry attempt number (0-indexed).
        base_delay: Base delay in seconds. Defaults to BASE_DELAY_SECONDS.
        max_delay: Maximum delay cap in seconds. Defaults to MAX_DELAY_SECONDS.

    Returns:
        The calculated delay in seconds.
    """
    if base_delay is None:
        base_delay = BASE_DELAY_SECONDS
    if max_delay is None:
        max_delay = MAX_DELAY_SECONDS

    delay = min(max_delay, base_delay * (2 ** attempt))
    return random.uniform(0, delay)


def build_dynamodb_item(record):
    """Prepare a DynamoDB item from an SQS message record.

    Parses the SQS message body, enriches it with a request timestamp
    and sets the initial status to PENDING_REVIEW.

    Args:
        record: A single SQS event record containing the book request data.

    Returns:
        A dictionary representing the DynamoDB item.

    Raises:
        json.JSONDecodeError: If the message body is not valid JSON.
        KeyError: If required fields are missing from the message.
    """
    body = json.loads(record["body"])

    item = {
        "requestId": body["requestId"],
        "title": body["title"],
        "author": body["author"],
        "isbn": body["isbn"],
        "status": "PENDING_REVIEW",
        "requestTimestamp": datetime.now(timezone.utc).isoformat(),
        "createdAt": body.get("createdAt", datetime.now(timezone.utc).isoformat()),
    }

    if body.get("notes"):
        item["notes"] = body["notes"]

    return item


def _is_retryable_error(error):
    """Determine if a ClientError is transient and safe to retry.

    Args:
        error: A botocore ClientError exception.

    Returns:
        True if the error code is in the set of retryable errors.
    """
    error_code = error.response["Error"].get("Code", "")
    return error_code in RETRYABLE_ERROR_CODES


def store_item_with_retry(item, dynamodb_client=None, max_retries=None,
                          base_delay=None, max_delay=None, _sleep_fn=time.sleep):
    """Store an enriched book request item in DynamoDB with exponential backoff.

    Retries transient errors (throttling, throughput exceeded, etc.) up to
    max_retries times using exponential backoff with jitter. Non-retryable
    errors are raised immediately.

    Args:
        item: Dictionary containing the DynamoDB item to store.
        dynamodb_client: Optional boto3 DynamoDB resource for dependency injection.
        max_retries: Maximum number of retry attempts. Defaults to MAX_RETRIES.
        base_delay: Base delay for backoff calculation. Defaults to BASE_DELAY_SECONDS.
        max_delay: Maximum delay cap. Defaults to MAX_DELAY_SECONDS.
        _sleep_fn: Sleep function for dependency injection in tests.

    Returns:
        The DynamoDB put_item response.

    Raises:
        ClientError: If a non-retryable error occurs or max retries are exhausted.
        ConnectTimeoutError: If the connection to DynamoDB times out after retries.
        ReadTimeoutError: If reading from DynamoDB times out after retries.
    """
    if max_retries is None:
        max_retries = MAX_RETRIES
    if dynamodb_client is None:
        dynamodb_client = boto3.resource("dynamodb", config=BOTO3_CONFIG)

    table_name = _get_table_name()
    table = dynamodb_client.Table(table_name)
    request_id = item.get("requestId", "unknown")

    last_exception = None

    for attempt in range(max_retries + 1):
        try:
            if attempt > 0:
                delay = calculate_backoff(attempt - 1, base_delay, max_delay)
                logger.info(
                    "Retry attempt %d/%d for requestId: %s, backoff: %.3fs",
                    attempt,
                    max_retries,
                    request_id,
                    delay,
                )
                _sleep_fn(delay)

            logger.info(
                "Storing item in DynamoDB table: %s, requestId: %s, attempt: %d",
                table_name,
                request_id,
                attempt + 1,
            )

            response = table.put_item(Item=item)

            logger.info(
                "Item stored successfully. requestId: %s",
                request_id,
            )

            return response

        except ClientError as e:
            last_exception = e
            error_code = e.response["Error"].get("Code", "")
            error_message = e.response["Error"].get("Message", "")

            if _is_retryable_error(e) and attempt < max_retries:
                logger.warning(
                    "Retryable DynamoDB error for requestId: %s, "
                    "error_code: %s, error_message: %s, attempt: %d/%d",
                    request_id,
                    error_code,
                    error_message,
                    attempt + 1,
                    max_retries + 1,
                )
                continue

            logger.error(
                "DynamoDB error for requestId: %s, "
                "error_code: %s, error_message: %s, "
                "attempts_exhausted: %s, total_attempts: %d",
                request_id,
                error_code,
                error_message,
                str(attempt >= max_retries),
                attempt + 1,
            )
            raise

        except (ConnectTimeoutError, ReadTimeoutError) as e:
            last_exception = e

            if attempt < max_retries:
                logger.warning(
                    "Timeout error for requestId: %s, "
                    "error_type: %s, error_message: %s, attempt: %d/%d",
                    request_id,
                    type(e).__name__,
                    str(e),
                    attempt + 1,
                    max_retries + 1,
                )
                continue

            logger.error(
                "Timeout error for requestId: %s, "
                "error_type: %s, error_message: %s, "
                "attempts_exhausted: True, total_attempts: %d",
                request_id,
                type(e).__name__,
                str(e),
                attempt + 1,
            )
            raise

    raise last_exception


def lambda_handler(event, context):
    """Main Lambda handler for processing SQS book request messages.

    Processes each record from the SQS event, builds a DynamoDB item,
    and stores it with retry logic. Returns batch item failures for
    partial batch response, which enables SQS to route failed messages
    to the Dead Letter Queue after maxReceiveCount attempts.

    Args:
        event: SQS event containing one or more records.
        context: Lambda context object.

    Returns:
        A dictionary with batchItemFailures for any records that failed processing.
    """
    logger.info("Received event with %d record(s)", len(event.get("Records", [])))

    batch_item_failures = []

    for record in event.get("Records", []):
        message_id = record.get("messageId", "unknown")

        try:
            logger.info("Processing record messageId: %s", message_id)
            item = build_dynamodb_item(record)
            store_item_with_retry(item)
            logger.info(
                "Successfully processed record messageId: %s, requestId: %s",
                message_id,
                item.get("requestId"),
            )

        except (json.JSONDecodeError, KeyError) as e:
            logger.error(
                "Invalid message format for messageId: %s, "
                "error_type: %s, error_message: %s",
                message_id,
                type(e).__name__,
                str(e),
            )
            batch_item_failures.append({"itemIdentifier": message_id})

        except ClientError as e:
            error_code = e.response["Error"].get("Code", "")
            logger.error(
                "DynamoDB error after retries for messageId: %s, "
                "error_code: %s, error_message: %s",
                message_id,
                error_code,
                str(e),
            )
            batch_item_failures.append({"itemIdentifier": message_id})

        except (ConnectTimeoutError, ReadTimeoutError) as e:
            logger.error(
                "Timeout after retries for messageId: %s, "
                "error_type: %s, error_message: %s",
                message_id,
                type(e).__name__,
                str(e),
            )
            batch_item_failures.append({"itemIdentifier": message_id})

        except Exception as e:
            logger.error(
                "Unexpected error for messageId: %s, "
                "error_type: %s, error_message: %s",
                message_id,
                type(e).__name__,
                str(e),
            )
            batch_item_failures.append({"itemIdentifier": message_id})

    logger.info(
        "Processing complete. Total: %d, Failed: %d",
        len(event.get("Records", [])),
        len(batch_item_failures),
    )

    return {"batchItemFailures": batch_item_failures}
