import json
import logging
import os
import boto3
import uuid
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
sqs = boto3.client('sqs')

# Environment variables
SQS_QUEUE_URL = os.environ['SQS_QUEUE_URL']
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event, context):
    """
    Producer Lambda - Receives book requests via API Gateway
    Validates input and sends to SQS for processing
    """
    logger.info(f"Received event: {json.dumps(event)}")

    try:
        # Parse request body (API Gateway REST API format)
        if 'body' in event:
            if event.get('isBase64Encoded', False):
                import base64
                body = base64.b64decode(event['body']).decode('utf-8')
            else:
                body = event['body']

            if isinstance(body, str):
                try:
                    request_data = json.loads(body)
                except json.JSONDecodeError:
                    return respond(400, {'error': 'Invalid JSON in request body'})
            else:
                request_data = body
        else:
            # Direct invocation (for testing)
            request_data = event

        # Validate required fields
        validation_result = validate_request(request_data)
        if not validation_result['valid']:
            return respond(400, {'error': validation_result['message']})

        # Prepare and send SQS message
        message = prepare_sqs_message(request_data)

        response = sqs.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(message),
            MessageAttributes={
                'Source': {
                    'DataType': 'String',
                    'StringValue': 'api-gateway'
                },
                'Environment': {
                    'DataType': 'String',
                    'StringValue': ENVIRONMENT
                }
            }
        )

        logger.info(f"Message sent to SQS: {response['MessageId']}")

        return respond(202, {
            'message': 'Book request accepted for processing',
            'requestId': message['requestId'],
            'sqsMessageId': response['MessageId']
        })

    except Exception as e:
        logger.error(f"Error processing request: {str(e)}", exc_info=True)
        return respond(500, {'error': 'Internal server error'})


def validate_request(data: dict) -> dict:
    """
    Validate the incoming request data.
    - requesterEmail is always required
    - At least one search param must be provided: isbn, authors, or query
    """
    # requesterEmail always required
    if 'requesterEmail' not in data:
        return {'valid': False, 'message': 'Missing required field: requesterEmail'}

    # Basic email validation
    email = data['requesterEmail']
    if '@' not in email or '.' not in email:
        return {'valid': False, 'message': 'Invalid email format'}

    # At least one search parameter required
    has_isbn   = bool(data.get('isbn', '').strip())
    has_authors = bool(data.get('authors', '').strip())
    has_query  = bool(data.get('query', '').strip())

    if not any([has_isbn, has_authors, has_query]):
        return {
            'valid': False,
            'message': 'At least one search parameter required: isbn, authors, or query'
        }

    # ISBN validation only when provided
    if has_isbn:
        isbn = data['isbn'].replace('-', '').strip()
        if not isbn.isdigit() or len(isbn) not in (10, 13):
            return {'valid': False, 'message': 'Invalid ISBN format. Must be 10 or 13 digits'}

    return {'valid': True, 'message': 'OK'}


def prepare_sqs_message(request_data: dict) -> dict:
    """
    Prepare the message structure for SQS.
    Mirrors the 3 BigBookAPI search params: isbn, authors, query
    """
    isbn = request_data.get('isbn', '').replace('-', '').strip()

    return {
        'requestId':      str(uuid.uuid4()),
        'requesterEmail': request_data['requesterEmail'],
        # BigBookAPI search params
        'isbn':           isbn,
        'authors':        request_data.get('authors', '').strip(),
        'query':          request_data.get('query', '').strip(),
        # Extra metadata
        'notes':          request_data.get('notes', ''),
        'requestDate':    datetime.utcnow().isoformat(),
        'source':         'api-gateway'
    }


def respond(status_code: int, data: dict) -> dict:
    """
    Format API Gateway response
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS'
        },
        'body': json.dumps(data)
    }


# For local testing
if __name__ == '__main__':
    test_cases = [
        # Search by ISBN only
        {'isbn': '9780451524935', 'requesterEmail': 'user@example.com'},
        # Search by query only
        {'query': 'dystopian novels', 'requesterEmail': 'user@example.com'},
        # Search by authors only
        {'authors': 'J.K. Rowling', 'requesterEmail': 'user@example.com'},
        # All 3 params
        {'isbn': '9781781257654', 'authors': 'J.K. Rowling', 'query': 'wizards', 'requesterEmail': 'user@example.com'},
        # Should fail - no search param
        {'requesterEmail': 'user@example.com'},
        # Should fail - no email
        {'isbn': '9780451524935'},
    ]

    for test in test_cases:
        event = {'body': json.dumps(test)}
        result = lambda_handler(event, None)
        print(json.dumps(result, indent=2))