"""Consumer Lambda function for the Library Book Request System.

This Lambda function processes book request messages from an SQS queue,
enriches the data with a request timestamp and initial review status,
and stores the item in DynamoDB.
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _get_table_name():
    """Get the DynamoDB table name from environment variables."""
    return os.environ.get("DYNAMODB_TABLE_NAME", "")


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
        # Transition from producer's PENDING to PENDING_REVIEW once queued for review
        "status": "PENDING_REVIEW",
        "requestTimestamp": datetime.now(timezone.utc).isoformat(),
        "createdAt": body.get("createdAt", datetime.now(timezone.utc).isoformat()),
    }

    if body.get("notes"):
        item["notes"] = body["notes"]

    return item


def store_item(item, dynamodb_client=None):
    """Store an enriched book request item in DynamoDB.

    Args:
        item: Dictionary containing the DynamoDB item to store.
        dynamodb_client: Optional boto3 DynamoDB resource for dependency injection.

    Returns:
        The DynamoDB put_item response.

    Raises:
        ClientError: If the DynamoDB put_item operation fails.
    """
    if dynamodb_client is None:
        dynamodb_client = boto3.resource("dynamodb")

    table_name = _get_table_name()
    table = dynamodb_client.Table(table_name)

    logger.info(
        "Storing item in DynamoDB table: %s, requestId: %s",
        table_name,
        item.get("requestId"),
    )

    response = table.put_item(Item=item)

    logger.info(
        "Item stored successfully. requestId: %s",
        item.get("requestId"),
    )

    return response


def lambda_handler(event, context):
    """Main Lambda handler for processing SQS book request messages.

    Processes each record from the SQS event, builds a DynamoDB item,
    and stores it. Returns batch item failures for partial batch response.

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
            store_item(item)
            logger.info(
                "Successfully processed record messageId: %s, requestId: %s",
                message_id,
                item.get("requestId"),
            )

        except (json.JSONDecodeError, KeyError) as e:
            logger.error(
                "Invalid message format for messageId %s: %s",
                message_id,
                str(e),
            )
            batch_item_failures.append({"itemIdentifier": message_id})

        except ClientError as e:
            logger.error(
                "DynamoDB error for messageId %s: %s",
                message_id,
                str(e),
            )
            batch_item_failures.append({"itemIdentifier": message_id})

        except Exception as e:
            logger.error(
                "Unexpected error for messageId %s: %s",
                message_id,
                str(e),
            )
            batch_item_failures.append({"itemIdentifier": message_id})

    logger.info(
        "Processing complete. Total: %d, Failed: %d",
        len(event.get("Records", [])),
        len(batch_item_failures),
    )

    return {"batchItemFailures": batch_item_failures}
