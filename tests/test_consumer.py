"""Unit tests for the Consumer Lambda function."""

import json
import os
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest
from botocore.exceptions import ClientError

from src.consumer.lambda_function import (
    build_dynamodb_item,
    lambda_handler,
    store_item,
)


# ---------------------------------------------------------------------------
# Helper to build SQS event records
# ---------------------------------------------------------------------------

def _make_sqs_record(body, message_id="test-message-id"):
    """Build a minimal SQS event record."""
    return {
        "messageId": message_id,
        "body": json.dumps(body) if isinstance(body, dict) else body,
    }


def _make_sqs_event(records):
    """Wrap records into an SQS event."""
    return {"Records": records}


VALID_BODY = {
    "requestId": "req-123",
    "title": "Clean Code",
    "author": "Robert Martin",
    "isbn": "9780132350884",
    "createdAt": "2026-01-01T00:00:00+00:00",
}


# ---------------------------------------------------------------------------
# build_dynamodb_item tests
# ---------------------------------------------------------------------------

class TestBuildDynamodbItem:
    """Tests for preparing the DynamoDB item from an SQS record."""

    def test_item_contains_required_fields(self):
        record = _make_sqs_record(VALID_BODY)
        item = build_dynamodb_item(record)

        assert item["requestId"] == "req-123"
        assert item["title"] == "Clean Code"
        assert item["author"] == "Robert Martin"
        assert item["isbn"] == "9780132350884"

    def test_status_set_to_pending_review(self):
        record = _make_sqs_record(VALID_BODY)
        item = build_dynamodb_item(record)

        assert item["status"] == "PENDING_REVIEW"

    def test_status_overrides_original(self):
        body = {**VALID_BODY, "status": "PENDING"}
        record = _make_sqs_record(body)
        item = build_dynamodb_item(record)

        assert item["status"] == "PENDING_REVIEW"

    def test_request_timestamp_added(self):
        record = _make_sqs_record(VALID_BODY)
        item = build_dynamodb_item(record)

        assert "requestTimestamp" in item
        # Verify it is a valid ISO-format timestamp
        datetime.fromisoformat(item["requestTimestamp"])

    def test_created_at_preserved(self):
        record = _make_sqs_record(VALID_BODY)
        item = build_dynamodb_item(record)

        assert item["createdAt"] == "2026-01-01T00:00:00+00:00"

    def test_created_at_defaults_when_missing(self):
        body = {k: v for k, v in VALID_BODY.items() if k != "createdAt"}
        record = _make_sqs_record(body)
        item = build_dynamodb_item(record)

        assert "createdAt" in item
        datetime.fromisoformat(item["createdAt"])

    def test_notes_included_when_present(self):
        body = {**VALID_BODY, "notes": "Urgent request"}
        record = _make_sqs_record(body)
        item = build_dynamodb_item(record)

        assert item["notes"] == "Urgent request"

    def test_notes_excluded_when_absent(self):
        record = _make_sqs_record(VALID_BODY)
        item = build_dynamodb_item(record)

        assert "notes" not in item

    def test_invalid_json_raises(self):
        record = {"messageId": "msg-1", "body": "not-json"}

        with pytest.raises(json.JSONDecodeError):
            build_dynamodb_item(record)

    def test_missing_required_field_raises(self):
        incomplete = {"requestId": "req-1", "title": "Book"}
        record = _make_sqs_record(incomplete)

        with pytest.raises(KeyError):
            build_dynamodb_item(record)


# ---------------------------------------------------------------------------
# store_item tests
# ---------------------------------------------------------------------------

class TestStoreItem:
    """Tests for storing items in DynamoDB."""

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_store_item_success(self):
        mock_table = MagicMock()
        mock_table.put_item.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        item = {
            "requestId": "req-123",
            "title": "Clean Code",
            "author": "Robert Martin",
            "isbn": "9780132350884",
            "status": "PENDING_REVIEW",
            "requestTimestamp": "2026-01-01T00:00:00+00:00",
            "createdAt": "2026-01-01T00:00:00+00:00",
        }

        response = store_item(item, dynamodb_client=mock_dynamodb)

        mock_dynamodb.Table.assert_called_once_with("BooksRequest-dev")
        mock_table.put_item.assert_called_once_with(Item=item)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_store_item_client_error(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = ClientError(
            {"Error": {"Code": "ConditionalCheckFailedException", "Message": "Condition not met"}},
            "PutItem",
        )

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        item = {"requestId": "req-456", "title": "Test"}

        with pytest.raises(ClientError):
            store_item(item, dynamodb_client=mock_dynamodb)


# ---------------------------------------------------------------------------
# Lambda handler integration tests
# ---------------------------------------------------------------------------

class TestLambdaHandler:
    """Tests for the main Lambda handler function."""

    @patch("src.consumer.lambda_function.store_item")
    def test_successful_single_record(self, mock_store):
        mock_store.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        event = _make_sqs_event([_make_sqs_record(VALID_BODY)])
        result = lambda_handler(event, None)

        assert result["batchItemFailures"] == []
        mock_store.assert_called_once()

    @patch("src.consumer.lambda_function.store_item")
    def test_successful_multiple_records(self, mock_store):
        mock_store.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        records = [
            _make_sqs_record(VALID_BODY, message_id="msg-1"),
            _make_sqs_record({**VALID_BODY, "requestId": "req-456"}, message_id="msg-2"),
        ]
        event = _make_sqs_event(records)
        result = lambda_handler(event, None)

        assert result["batchItemFailures"] == []
        assert mock_store.call_count == 2

    @patch("src.consumer.lambda_function.store_item")
    def test_invalid_json_record_reported_as_failure(self, mock_store):
        record = {"messageId": "msg-bad", "body": "not-json"}
        event = _make_sqs_event([record])

        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-bad"
        mock_store.assert_not_called()

    @patch("src.consumer.lambda_function.store_item")
    def test_missing_field_reported_as_failure(self, mock_store):
        incomplete = {"requestId": "req-1"}
        event = _make_sqs_event([_make_sqs_record(incomplete, message_id="msg-inc")])

        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-inc"
        mock_store.assert_not_called()

    @patch("src.consumer.lambda_function.store_item")
    def test_dynamodb_error_reported_as_failure(self, mock_store):
        mock_store.side_effect = ClientError(
            {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "Throughput exceeded"}},
            "PutItem",
        )

        event = _make_sqs_event([_make_sqs_record(VALID_BODY, message_id="msg-ddb")])
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-ddb"

    @patch("src.consumer.lambda_function.store_item")
    def test_partial_batch_failure(self, mock_store):
        """One record succeeds, one fails — only the failed one is reported."""
        mock_store.side_effect = [
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
            ClientError(
                {"Error": {"Code": "InternalServerError", "Message": "DDB error"}},
                "PutItem",
            ),
        ]

        records = [
            _make_sqs_record(VALID_BODY, message_id="msg-ok"),
            _make_sqs_record({**VALID_BODY, "requestId": "req-456"}, message_id="msg-fail"),
        ]
        event = _make_sqs_event(records)
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-fail"

    @patch("src.consumer.lambda_function.store_item")
    def test_empty_event(self, mock_store):
        event = _make_sqs_event([])
        result = lambda_handler(event, None)

        assert result["batchItemFailures"] == []
        mock_store.assert_not_called()

    @patch("src.consumer.lambda_function.store_item")
    def test_item_has_pending_review_status(self, mock_store):
        mock_store.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        event = _make_sqs_event([_make_sqs_record(VALID_BODY)])
        lambda_handler(event, None)

        stored_item = mock_store.call_args[0][0]
        assert stored_item["status"] == "PENDING_REVIEW"

    @patch("src.consumer.lambda_function.store_item")
    def test_item_has_request_timestamp(self, mock_store):
        mock_store.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        event = _make_sqs_event([_make_sqs_record(VALID_BODY)])
        lambda_handler(event, None)

        stored_item = mock_store.call_args[0][0]
        assert "requestTimestamp" in stored_item
        datetime.fromisoformat(stored_item["requestTimestamp"])

    @patch("src.consumer.lambda_function.store_item")
    def test_unexpected_error_reported_as_failure(self, mock_store):
        mock_store.side_effect = RuntimeError("Something went wrong")

        event = _make_sqs_event([_make_sqs_record(VALID_BODY, message_id="msg-err")])
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-err"
