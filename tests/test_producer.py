"""Unit tests for the Producer Lambda function."""

import json
import os
from unittest.mock import MagicMock, patch

import pytest

from src.producer.lambda_function import (
    _validate_isbn10_checksum,
    _validate_isbn13_checksum,
    build_response,
    lambda_handler,
    send_to_sqs,
    validate_isbn,
    validate_request,
)


# ---------------------------------------------------------------------------
# ISBN validation tests
# ---------------------------------------------------------------------------

class TestValidateIsbn:
    """Tests for ISBN format and checksum validation."""

    def test_valid_isbn13(self):
        assert validate_isbn("9780306406157") is True

    def test_valid_isbn13_with_hyphens(self):
        assert validate_isbn("978-0-306-40615-7") is True

    def test_valid_isbn10(self):
        assert validate_isbn("0306406152") is True

    def test_valid_isbn10_with_hyphens(self):
        assert validate_isbn("0-306-40615-2") is True

    def test_valid_isbn10_ending_x(self):
        assert validate_isbn("007462542X") is True

    def test_valid_isbn10_ending_lowercase_x(self):
        assert validate_isbn("007462542x") is True

    def test_invalid_isbn_too_short(self):
        assert validate_isbn("12345") is False

    def test_invalid_isbn_too_long(self):
        assert validate_isbn("12345678901234") is False

    def test_invalid_isbn_letters(self):
        assert validate_isbn("abcdefghij") is False

    def test_invalid_isbn13_bad_checksum(self):
        assert validate_isbn("9780306406158") is False

    def test_invalid_isbn10_bad_checksum(self):
        assert validate_isbn("0306406153") is False

    def test_empty_string(self):
        assert validate_isbn("") is False


class TestIsbn10Checksum:
    """Tests for the ISBN-10 checksum algorithm."""

    def test_valid_checksum(self):
        assert _validate_isbn10_checksum("0306406152") is True

    def test_invalid_checksum(self):
        assert _validate_isbn10_checksum("0306406153") is False

    def test_x_check_digit(self):
        assert _validate_isbn10_checksum("007462542X") is True


class TestIsbn13Checksum:
    """Tests for the ISBN-13 checksum algorithm."""

    def test_valid_checksum(self):
        assert _validate_isbn13_checksum("9780306406157") is True

    def test_invalid_checksum(self):
        assert _validate_isbn13_checksum("9780306406158") is False


# ---------------------------------------------------------------------------
# Request validation tests
# ---------------------------------------------------------------------------

class TestValidateRequest:
    """Tests for request body validation."""

    def test_valid_request(self):
        body = {"title": "Clean Code", "author": "Robert Martin", "isbn": "9780132350884"}
        is_valid, errors = validate_request(body)
        assert is_valid is True
        assert errors == []

    def test_missing_title(self):
        body = {"author": "Robert Martin", "isbn": "9780132350884"}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert any("title" in e for e in errors)

    def test_missing_author(self):
        body = {"title": "Clean Code", "isbn": "9780132350884"}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert any("author" in e for e in errors)

    def test_missing_isbn(self):
        body = {"title": "Clean Code", "author": "Robert Martin"}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert any("isbn" in e for e in errors)

    def test_empty_title(self):
        body = {"title": "", "author": "Robert Martin", "isbn": "9780132350884"}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert any("title" in e for e in errors)

    def test_whitespace_only_field(self):
        body = {"title": "   ", "author": "Robert Martin", "isbn": "9780132350884"}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert any("title" in e for e in errors)

    def test_invalid_isbn_format(self):
        body = {"title": "Clean Code", "author": "Robert Martin", "isbn": "invalid-isbn"}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert any("ISBN" in e for e in errors)

    def test_multiple_missing_fields(self):
        body = {}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert len(errors) == 3

    def test_all_fields_empty(self):
        body = {"title": "", "author": "", "isbn": ""}
        is_valid, errors = validate_request(body)
        assert is_valid is False
        assert len(errors) == 3


# ---------------------------------------------------------------------------
# Build response tests
# ---------------------------------------------------------------------------

class TestBuildResponse:
    """Tests for the API Gateway response builder."""

    def test_success_response(self):
        response = build_response(200, {"message": "OK"})
        assert response["statusCode"] == 200
        assert response["headers"]["Content-Type"] == "application/json"
        assert json.loads(response["body"]) == {"message": "OK"}

    def test_error_response(self):
        response = build_response(400, {"message": "Bad Request"})
        assert response["statusCode"] == 400
        body = json.loads(response["body"])
        assert body["message"] == "Bad Request"


# ---------------------------------------------------------------------------
# Send to SQS tests
# ---------------------------------------------------------------------------

class TestSendToSqs:
    """Tests for the SQS message sending function."""

    @patch.dict(os.environ, {"SQS_QUEUE_URL": "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"})
    def test_send_to_sqs_success(self):
        mock_sqs = MagicMock()
        mock_sqs.send_message.return_value = {"MessageId": "test-msg-id"}

        message = {
            "requestId": "test-request-id",
            "title": "Clean Code",
            "author": "Robert Martin",
            "isbn": "9780132350884",
        }

        response = send_to_sqs(message, sqs_client=mock_sqs)
        assert response["MessageId"] == "test-msg-id"

        mock_sqs.send_message.assert_called_once()
        call_kwargs = mock_sqs.send_message.call_args[1]
        assert call_kwargs["QueueUrl"] == "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"
        body = json.loads(call_kwargs["MessageBody"])
        assert body["requestId"] == "test-request-id"

    @patch.dict(os.environ, {"SQS_QUEUE_URL": "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"})
    def test_send_to_sqs_includes_message_attributes(self):
        mock_sqs = MagicMock()
        mock_sqs.send_message.return_value = {"MessageId": "test-msg-id"}

        message = {"requestId": "req-123", "title": "Test", "author": "Author", "isbn": "1234567890"}

        send_to_sqs(message, sqs_client=mock_sqs)

        call_kwargs = mock_sqs.send_message.call_args[1]
        assert call_kwargs["MessageAttributes"]["requestId"]["StringValue"] == "req-123"


# ---------------------------------------------------------------------------
# Lambda handler integration tests
# ---------------------------------------------------------------------------

class TestLambdaHandler:
    """Tests for the main Lambda handler function."""

    @patch("src.producer.lambda_function.send_to_sqs")
    @patch.dict(os.environ, {"SQS_QUEUE_URL": "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"})
    def test_successful_request(self, mock_send):
        mock_send.return_value = {"MessageId": "test-msg-id"}

        event = {
            "body": json.dumps({
                "title": "Clean Code",
                "author": "Robert Martin",
                "isbn": "9780132350884",
            })
        }

        response = lambda_handler(event, None)
        assert response["statusCode"] == 200

        body = json.loads(response["body"])
        assert body["message"] == "Book request submitted successfully."
        assert "requestId" in body

        mock_send.assert_called_once()

    @patch("src.producer.lambda_function.send_to_sqs")
    @patch.dict(os.environ, {"SQS_QUEUE_URL": "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"})
    def test_successful_request_with_notes(self, mock_send):
        mock_send.return_value = {"MessageId": "test-msg-id"}

        event = {
            "body": json.dumps({
                "title": "Clean Code",
                "author": "Robert Martin",
                "isbn": "9780132350884",
                "notes": "Need this for the programming book club.",
            })
        }

        response = lambda_handler(event, None)
        assert response["statusCode"] == 200

        sent_message = mock_send.call_args[0][0]
        assert sent_message["notes"] == "Need this for the programming book club."

    def test_invalid_json_body(self):
        event = {"body": "not valid json"}
        response = lambda_handler(event, None)
        assert response["statusCode"] == 400
        body = json.loads(response["body"])
        assert "Invalid JSON" in body["message"]

    def test_missing_required_fields(self):
        event = {"body": json.dumps({"title": "Clean Code"})}
        response = lambda_handler(event, None)
        assert response["statusCode"] == 400
        body = json.loads(response["body"])
        assert body["message"] == "Validation failed."
        assert len(body["errors"]) > 0

    def test_invalid_isbn(self):
        event = {
            "body": json.dumps({
                "title": "Clean Code",
                "author": "Robert Martin",
                "isbn": "invalid",
            })
        }
        response = lambda_handler(event, None)
        assert response["statusCode"] == 400
        body = json.loads(response["body"])
        assert any("ISBN" in e for e in body["errors"])

    @patch("src.producer.lambda_function.send_to_sqs")
    @patch.dict(os.environ, {"SQS_QUEUE_URL": "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"})
    def test_sqs_failure(self, mock_send):
        from botocore.exceptions import ClientError

        mock_send.side_effect = ClientError(
            {"Error": {"Code": "ServiceException", "Message": "SQS error"}},
            "SendMessage",
        )

        event = {
            "body": json.dumps({
                "title": "Clean Code",
                "author": "Robert Martin",
                "isbn": "9780132350884",
            })
        }

        response = lambda_handler(event, None)
        assert response["statusCode"] == 500
        body = json.loads(response["body"])
        assert "Failed to process" in body["message"]

    def test_empty_body(self):
        event = {"body": ""}
        response = lambda_handler(event, None)
        assert response["statusCode"] == 400

    def test_body_as_dict(self):
        """API Gateway may pass body as already-parsed dict."""
        event = {
            "body": {
                "title": "Clean Code",
                "author": "Robert Martin",
                "isbn": "9780132350884",
            }
        }
        with patch("src.producer.lambda_function.send_to_sqs") as mock_send:
            mock_send.return_value = {"MessageId": "test-msg-id"}
            response = lambda_handler(event, None)
            assert response["statusCode"] == 200

    @patch("src.producer.lambda_function.send_to_sqs")
    @patch.dict(os.environ, {"SQS_QUEUE_URL": "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"})
    def test_response_contains_unique_request_ids(self, mock_send):
        mock_send.return_value = {"MessageId": "test-msg-id"}

        event = {
            "body": json.dumps({
                "title": "Clean Code",
                "author": "Robert Martin",
                "isbn": "9780132350884",
            })
        }

        response1 = lambda_handler(event, None)
        response2 = lambda_handler(event, None)

        id1 = json.loads(response1["body"])["requestId"]
        id2 = json.loads(response2["body"])["requestId"]
        assert id1 != id2

    @patch("src.producer.lambda_function.send_to_sqs")
    @patch.dict(os.environ, {"SQS_QUEUE_URL": "https://sqs.us-east-2.amazonaws.com/123456789/test-queue"})
    def test_message_contains_expected_fields(self, mock_send):
        mock_send.return_value = {"MessageId": "test-msg-id"}

        event = {
            "body": json.dumps({
                "title": "Clean Code",
                "author": "Robert Martin",
                "isbn": "9780132350884",
            })
        }

        lambda_handler(event, None)

        sent_message = mock_send.call_args[0][0]
        assert "requestId" in sent_message
        assert sent_message["title"] == "Clean Code"
        assert sent_message["author"] == "Robert Martin"
        assert sent_message["isbn"] == "9780132350884"
        assert sent_message["status"] == "PENDING"
        assert "createdAt" in sent_message

    def test_no_body_key(self):
        event = {}
        response = lambda_handler(event, None)
        assert response["statusCode"] == 400
