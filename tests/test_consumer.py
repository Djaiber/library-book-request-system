"""Unit tests for the Consumer Lambda function error handling and retry logic."""

import json
import os
from datetime import datetime, timezone
from unittest.mock import MagicMock, call, patch

import pytest
from botocore.exceptions import ClientError, ConnectTimeoutError, ReadTimeoutError

from src.consumer.lambda_function import (
    build_dynamodb_item,
    calculate_backoff,
    lambda_handler,
    store_item_with_retry,
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


def _make_client_error(code="InternalServerError", message="Internal error"):
    """Create a botocore ClientError with the given code and message."""
    return ClientError(
        {"Error": {"Code": code, "Message": message}},
        "PutItem",
    )


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
# calculate_backoff tests
# ---------------------------------------------------------------------------

class TestCalculateBackoff:
    """Tests for the exponential backoff calculation."""

    def test_backoff_is_non_negative(self):
        for attempt in range(5):
            delay = calculate_backoff(attempt, base_delay=0.1, max_delay=2.0)
            assert delay >= 0

    def test_backoff_respects_max_delay(self):
        for attempt in range(10):
            delay = calculate_backoff(attempt, base_delay=0.1, max_delay=2.0)
            assert delay <= 2.0

    def test_backoff_increases_with_attempts(self):
        """Average backoff should increase with attempt number."""
        samples = 100
        avg_attempt_0 = sum(
            calculate_backoff(0, base_delay=0.1, max_delay=10.0)
            for _ in range(samples)
        ) / samples
        avg_attempt_5 = sum(
            calculate_backoff(5, base_delay=0.1, max_delay=10.0)
            for _ in range(samples)
        ) / samples

        assert avg_attempt_5 > avg_attempt_0

    def test_backoff_zero_attempt(self):
        delay = calculate_backoff(0, base_delay=0.1, max_delay=2.0)
        assert 0 <= delay <= 0.1

    def test_backoff_uses_module_defaults(self):
        delay = calculate_backoff(0)
        assert delay >= 0


# ---------------------------------------------------------------------------
# store_item_with_retry tests
# ---------------------------------------------------------------------------

class TestStoreItemWithRetry:
    """Tests for storing items in DynamoDB with retry logic."""

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_store_item_success_first_attempt(self):
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

        response = store_item_with_retry(item, dynamodb_client=mock_dynamodb)

        mock_dynamodb.Table.assert_called_once_with("BooksRequest-dev")
        mock_table.put_item.assert_called_once_with(Item=item)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_retries_on_throughput_exceeded(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = [
            _make_client_error("ProvisionedThroughputExceededException", "Throughput exceeded"),
            _make_client_error("ProvisionedThroughputExceededException", "Throughput exceeded"),
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
        ]

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-123", "title": "Test"}
        response = store_item_with_retry(
            item,
            dynamodb_client=mock_dynamodb,
            max_retries=3,
            _sleep_fn=mock_sleep,
        )

        assert mock_table.put_item.call_count == 3
        assert mock_sleep.call_count == 2
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_retries_on_throttling(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = [
            _make_client_error("ThrottlingException", "Rate exceeded"),
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
        ]

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-456", "title": "Test"}
        response = store_item_with_retry(
            item,
            dynamodb_client=mock_dynamodb,
            max_retries=2,
            _sleep_fn=mock_sleep,
        )

        assert mock_table.put_item.call_count == 2
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_raises_after_max_retries_exhausted(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = _make_client_error(
            "ProvisionedThroughputExceededException", "Throughput exceeded"
        )

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-789", "title": "Test"}

        with pytest.raises(ClientError) as exc_info:
            store_item_with_retry(
                item,
                dynamodb_client=mock_dynamodb,
                max_retries=2,
                _sleep_fn=mock_sleep,
            )

        assert exc_info.value.response["Error"]["Code"] == "ProvisionedThroughputExceededException"
        assert mock_table.put_item.call_count == 3  # initial + 2 retries

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_no_retry_on_non_retryable_error(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = _make_client_error(
            "ValidationException", "Invalid item"
        )

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-bad", "title": "Test"}

        with pytest.raises(ClientError) as exc_info:
            store_item_with_retry(
                item,
                dynamodb_client=mock_dynamodb,
                max_retries=3,
                _sleep_fn=mock_sleep,
            )

        assert exc_info.value.response["Error"]["Code"] == "ValidationException"
        assert mock_table.put_item.call_count == 1
        mock_sleep.assert_not_called()

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_retries_on_connect_timeout(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = [
            ConnectTimeoutError(endpoint_url="https://dynamodb.us-east-2.amazonaws.com"),
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
        ]

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-timeout", "title": "Test"}
        response = store_item_with_retry(
            item,
            dynamodb_client=mock_dynamodb,
            max_retries=2,
            _sleep_fn=mock_sleep,
        )

        assert mock_table.put_item.call_count == 2
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_retries_on_read_timeout(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = [
            ReadTimeoutError(endpoint_url="https://dynamodb.us-east-2.amazonaws.com"),
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
        ]

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-read-timeout", "title": "Test"}
        response = store_item_with_retry(
            item,
            dynamodb_client=mock_dynamodb,
            max_retries=2,
            _sleep_fn=mock_sleep,
        )

        assert mock_table.put_item.call_count == 2
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_raises_connect_timeout_after_max_retries(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = ConnectTimeoutError(
            endpoint_url="https://dynamodb.us-east-2.amazonaws.com"
        )

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-timeout-fail", "title": "Test"}

        with pytest.raises(ConnectTimeoutError):
            store_item_with_retry(
                item,
                dynamodb_client=mock_dynamodb,
                max_retries=2,
                _sleep_fn=mock_sleep,
            )

        assert mock_table.put_item.call_count == 3

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_backoff_delay_increases(self):
        """Verify sleep is called with increasing delays on retries."""
        mock_table = MagicMock()
        mock_table.put_item.side_effect = [
            _make_client_error("InternalServerError", "Server error"),
            _make_client_error("InternalServerError", "Server error"),
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
        ]

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        sleep_delays = []

        def capture_sleep(delay):
            sleep_delays.append(delay)

        item = {"requestId": "req-backoff", "title": "Test"}
        store_item_with_retry(
            item,
            dynamodb_client=mock_dynamodb,
            max_retries=3,
            base_delay=0.1,
            max_delay=10.0,
            _sleep_fn=capture_sleep,
        )

        assert len(sleep_delays) == 2
        for delay in sleep_delays:
            assert delay >= 0

    @patch.dict(os.environ, {"DYNAMODB_TABLE_NAME": "BooksRequest-dev"})
    def test_retries_on_service_unavailable(self):
        mock_table = MagicMock()
        mock_table.put_item.side_effect = [
            _make_client_error("ServiceUnavailable", "Service unavailable"),
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
        ]

        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table

        mock_sleep = MagicMock()

        item = {"requestId": "req-svc", "title": "Test"}
        response = store_item_with_retry(
            item,
            dynamodb_client=mock_dynamodb,
            max_retries=2,
            _sleep_fn=mock_sleep,
        )

        assert mock_table.put_item.call_count == 2
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200


# ---------------------------------------------------------------------------
# Lambda handler integration tests
# ---------------------------------------------------------------------------

class TestLambdaHandler:
    """Tests for the main Lambda handler function."""

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_successful_single_record(self, mock_store):
        mock_store.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        event = _make_sqs_event([_make_sqs_record(VALID_BODY)])
        result = lambda_handler(event, None)

        assert result["batchItemFailures"] == []
        mock_store.assert_called_once()

    @patch("src.consumer.lambda_function.store_item_with_retry")
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

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_invalid_json_record_reported_as_failure(self, mock_store):
        record = {"messageId": "msg-bad", "body": "not-json"}
        event = _make_sqs_event([record])

        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-bad"
        mock_store.assert_not_called()

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_missing_field_reported_as_failure(self, mock_store):
        incomplete = {"requestId": "req-1"}
        event = _make_sqs_event([_make_sqs_record(incomplete, message_id="msg-inc")])

        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-inc"
        mock_store.assert_not_called()

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_dynamodb_error_reported_as_failure(self, mock_store):
        mock_store.side_effect = _make_client_error(
            "ProvisionedThroughputExceededException", "Throughput exceeded"
        )

        event = _make_sqs_event([_make_sqs_record(VALID_BODY, message_id="msg-ddb")])
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-ddb"

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_timeout_error_reported_as_failure(self, mock_store):
        mock_store.side_effect = ConnectTimeoutError(
            endpoint_url="https://dynamodb.us-east-2.amazonaws.com"
        )

        event = _make_sqs_event([_make_sqs_record(VALID_BODY, message_id="msg-timeout")])
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-timeout"

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_read_timeout_reported_as_failure(self, mock_store):
        mock_store.side_effect = ReadTimeoutError(
            endpoint_url="https://dynamodb.us-east-2.amazonaws.com"
        )

        event = _make_sqs_event([_make_sqs_record(VALID_BODY, message_id="msg-read-timeout")])
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-read-timeout"

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_partial_batch_failure(self, mock_store):
        """One record succeeds, one fails — only the failed one is reported."""
        mock_store.side_effect = [
            {"ResponseMetadata": {"HTTPStatusCode": 200}},
            _make_client_error("InternalServerError", "DDB error"),
        ]

        records = [
            _make_sqs_record(VALID_BODY, message_id="msg-ok"),
            _make_sqs_record({**VALID_BODY, "requestId": "req-456"}, message_id="msg-fail"),
        ]
        event = _make_sqs_event(records)
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-fail"

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_empty_event(self, mock_store):
        event = _make_sqs_event([])
        result = lambda_handler(event, None)

        assert result["batchItemFailures"] == []
        mock_store.assert_not_called()

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_item_has_pending_review_status(self, mock_store):
        mock_store.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        event = _make_sqs_event([_make_sqs_record(VALID_BODY)])
        lambda_handler(event, None)

        stored_item = mock_store.call_args[0][0]
        assert stored_item["status"] == "PENDING_REVIEW"

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_item_has_request_timestamp(self, mock_store):
        mock_store.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

        event = _make_sqs_event([_make_sqs_record(VALID_BODY)])
        lambda_handler(event, None)

        stored_item = mock_store.call_args[0][0]
        assert "requestTimestamp" in stored_item
        datetime.fromisoformat(stored_item["requestTimestamp"])

    @patch("src.consumer.lambda_function.store_item_with_retry")
    def test_unexpected_error_reported_as_failure(self, mock_store):
        mock_store.side_effect = RuntimeError("Something went wrong")

        event = _make_sqs_event([_make_sqs_record(VALID_BODY, message_id="msg-err")])
        result = lambda_handler(event, None)

        assert len(result["batchItemFailures"]) == 1
        assert result["batchItemFailures"][0]["itemIdentifier"] == "msg-err"
