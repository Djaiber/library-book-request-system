"""Producer Lambda function for the Library Book Request System.

This Lambda function handles incoming book request submissions from API Gateway.
It validates the request, generates a unique request ID, and sends the validated
request to an SQS queue for asynchronous processing.
"""

import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def _get_queue_url():
    """Get the SQS queue URL from environment variables."""
    return os.environ.get("SQS_QUEUE_URL", "")

REQUIRED_FIELDS = ["title", "author", "isbn"]

ISBN_10_PATTERN = re.compile(r"^\d{9}[\dXx]$")
ISBN_13_PATTERN = re.compile(r"^\d{13}$")


def validate_isbn(isbn):
    """Validate ISBN format (ISBN-10 or ISBN-13).

    Args:
        isbn: The ISBN string to validate.

    Returns:
        True if the ISBN is valid, False otherwise.
    """
    cleaned = isbn.replace("-", "").replace(" ", "")

    if ISBN_13_PATTERN.match(cleaned):
        return _validate_isbn13_checksum(cleaned)

    if ISBN_10_PATTERN.match(cleaned):
        return _validate_isbn10_checksum(cleaned)

    return False


def _validate_isbn10_checksum(isbn):
    """Validate ISBN-10 check digit.

    Args:
        isbn: A 10-character string of digits (last may be X).

    Returns:
        True if the checksum is valid.
    """
    total = 0
    for i in range(9):
        total += int(isbn[i]) * (10 - i)
    last = isbn[9].upper()
    total += 10 if last == "X" else int(last)
    return total % 11 == 0


def _validate_isbn13_checksum(isbn):
    """Validate ISBN-13 check digit.

    Args:
        isbn: A 13-character string of digits.

    Returns:
        True if the checksum is valid.
    """
    total = 0
    for i in range(12):
        total += int(isbn[i]) * (1 if i % 2 == 0 else 3)
    check = (10 - (total % 10)) % 10
    return check == int(isbn[12])


def validate_request(body):
    """Validate the incoming book request.

    Args:
        body: Dictionary containing the request fields.

    Returns:
        A tuple of (is_valid, errors) where errors is a list of error messages.
    """
    errors = []

    for field in REQUIRED_FIELDS:
        value = body.get(field)
        if not value or not str(value).strip():
            errors.append(f"Missing or empty required field: {field}")

    if body.get("isbn") and str(body["isbn"]).strip():
        if not validate_isbn(str(body["isbn"])):
            errors.append(
                "Invalid ISBN format. Must be a valid ISBN-10 or ISBN-13."
            )

    return len(errors) == 0, errors


def build_response(status_code, body):
    """Build a standardized API Gateway response.

    Args:
        status_code: HTTP status code.
        body: Response body dictionary.

    Returns:
        API Gateway-compatible response dictionary.
    """
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body),
    }


def send_to_sqs(message, sqs_client=None):
    """Send a validated book request message to SQS.

    Args:
        message: Dictionary containing the book request data.
        sqs_client: Optional boto3 SQS client for dependency injection.

    Returns:
        The SQS SendMessage response.

    Raises:
        ClientError: If the SQS send fails.
    """
    if sqs_client is None:
        sqs_client = boto3.client("sqs")

    queue_url = _get_queue_url()
    logger.info(
        "Sending message to SQS queue: %s, requestId: %s",
        queue_url,
        message.get("requestId"),
    )

    response = sqs_client.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(message),
        MessageAttributes={
            "requestId": {
                "DataType": "String",
                "StringValue": message["requestId"],
            },
        },
    )

    logger.info(
        "Message sent successfully. SQS MessageId: %s",
        response.get("MessageId"),
    )

    return response


def lambda_handler(event, context):
    """Main Lambda handler for processing book request submissions.

    Args:
        event: API Gateway event containing the HTTP request.
        context: Lambda context object.

    Returns:
        API Gateway-compatible response with status code and body.
    """
    logger.info("Received event: %s", json.dumps(event))

    try:
        body = event.get("body", "")
        if isinstance(body, str):
            body = json.loads(body) if body else {}
    except (json.JSONDecodeError, TypeError) as e:
        logger.error("Failed to parse request body: %s", str(e))
        return build_response(400, {
            "message": "Invalid JSON in request body.",
        })

    is_valid, errors = validate_request(body)
    if not is_valid:
        logger.warning("Request validation failed: %s", errors)
        return build_response(400, {
            "message": "Validation failed.",
            "errors": errors,
        })

    request_id = str(uuid.uuid4())
    logger.info("Generated requestId: %s", request_id)

    message = {
        "requestId": request_id,
        "title": body["title"].strip(),
        "author": body["author"].strip(),
        "isbn": str(body["isbn"]).strip(),
        "status": "PENDING",
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }

    if body.get("notes"):
        message["notes"] = str(body["notes"]).strip()

    try:
        send_to_sqs(message)
    except ClientError as e:
        logger.error("Failed to send message to SQS: %s", str(e))
        return build_response(500, {
            "message": "Failed to process book request. Please try again.",
        })
    except Exception as e:
        logger.error("Unexpected error sending to SQS: %s", str(e))
        return build_response(500, {
            "message": "An internal error occurred. Please try again.",
        })

    logger.info(
        "Book request processed successfully. requestId: %s", request_id
    )

    return build_response(200, {
        "message": "Book request submitted successfully.",
        "requestId": request_id,
    })
