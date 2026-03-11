import json
import logging
import os
import time
import boto3
import requests
from datetime import datetime
from typing import Dict, Any
from decimal import Decimal

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])
secretsmanager = boto3.client('secretsmanager')

# Environment variables
SECRET_ARN    = os.environ['SECRET_ARN']
BIGBOOK_API_URL = os.environ.get('BIGBOOK_API_URL', 'https://api.bigbookapi.com/search-books')
ENVIRONMENT   = os.environ.get('ENVIRONMENT', 'dev')
MAX_RETRIES   = int(os.environ.get('MAX_RETRIES', '3'))

# --- Fix #1: Fetch the real API key at cold start ---
def get_api_key() -> str:
    response = secretsmanager.get_secret_value(SecretId=SECRET_ARN)
    return response['SecretString']

BIGBOOK_API_KEY = get_api_key()  # Cached per container lifetime



def lambda_handler(event, context):
    """
    Consumer Lambda - Triggered by SQS
    Enriches book requests via BigBookAPI and stores in DynamoDB
    """
    logger.info(f"Received {len(event['Records'])} messages from SQS")

    batch_item_failures = []

    for record in event['Records']:
        message_id = record['messageId']
        try:
            message = json.loads(record['body'])
            logger.info(f"Processing message {message_id}: {json.dumps(message)}")

            result = process_book_request(message)

            if result['success']:
                logger.info(f"Successfully processed message {message_id}")
            else:
                logger.error(f"Failed to process message {message_id}: {result['error']}")
                batch_item_failures.append({'itemIdentifier': message_id})

        except Exception as e:
            logger.error(f"Unexpected error processing message {message_id}: {str(e)}", exc_info=True)
            batch_item_failures.append({'itemIdentifier': message_id})

    # SQS will retry failed items and route to DLQ after maxReceiveCount
    return {'batchItemFailures': batch_item_failures}

# Convert floats to Decimal for DynamoDB compatibility — BigBookAPI may return ratings as floats
def convert_floats(obj):
    """Recursively convert floats to Decimal for DynamoDB compatibility."""
    if isinstance(obj, float):
        return Decimal(str(obj))  # str() avoids floating point precision issues
    elif isinstance(obj, dict):
        return {k: convert_floats(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_floats(i) for i in obj]
    return obj

def process_book_request(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a single book request:
    1. Enrich with BigBookAPI data
    2. Store in DynamoDB
    """
    try:
        request_id      = request_data.get('requestId')
        isbn            = request_data.get('isbn', '').strip()
        authors         = request_data.get('authors', '').strip()
        query           = request_data.get('query', '').strip()
        requester_email = request_data.get('requesterEmail')
        notes           = request_data.get('notes', '')
        request_date    = request_data.get('requestDate', datetime.utcnow().isoformat())

        # Fix #3: only require requestId and email — isbn is now optional
        if not request_id or not requester_email:
            return {'success': False, 'error': 'Missing requestId or requesterEmail'}

        # Fix #2: pass all 3 search params to API
        book_data = enrich_book_data(isbn=isbn, authors=authors, query=query)

        books = book_data.get('books', [])
        status = 'COMPLETED' if books else 'NOT_FOUND'

        item = {
            'requestId':    request_id,
            'status':       status,
            'createdAt':    request_date,
            'requesterEmail': requester_email,
            'isbn':         isbn,
            'authors':      authors,
            'query':        query,
            'notes':        notes,
            'processedAt':  datetime.utcnow().isoformat(),
            'environment':  ENVIRONMENT,
            # TTL: 30 days
            'ttl': int(datetime.utcnow().timestamp()) + (30 * 24 * 60 * 60)
        }

        if books:
            # BigBookAPI returns nested lists — flatten safely
            first_book = books[0][0] if isinstance(books[0], list) else books[0]
            item.update({
                'bookId': str(first_book.get('id', '')),
                'bookData': {
                    'id':      first_book.get('id'),
                    'title':   first_book.get('title'),
                    'image':   first_book.get('image'),
                    'authors': first_book.get('authors', []),
                    'rating':  first_book.get('rating', {})
                },
                'apiResponse': {
                    'available': book_data.get('available', 0),
                    'number':    book_data.get('number', 0),
                    'offset':    book_data.get('offset', 0)
                }
            })
        
        item = convert_floats(item)  # Ensure all floats are converted to Decimal for DynamoDB

        table.put_item(Item=item)
        logger.info(f"Stored DynamoDB item for request {request_id} — status: {status}")

        return {'success': True, 'request_id': request_id, 'book_found': bool(books)}

    except Exception as e:
        logger.error(f"Error processing book request: {str(e)}", exc_info=True)
        return {'success': False, 'error': str(e)}


def enrich_book_data(isbn: str, authors: str = '', query: str = '') -> Dict[str, Any]:
    """
    Call BigBookAPI using whichever search params are available.
    Priority: isbn > authors > query
    """
    headers = {
        'x-api-key': BIGBOOK_API_KEY,  # Fix #1: real key, not ARN
        'Content-Type': 'application/json'
    }

    # Build params — mirror BigBookAPI's 3 supported search fields
    params: Dict[str, Any] = {'number': 1}

    if isbn:
        params['isbn'] = isbn
    if authors:
        params['authors'] = authors
    if query:
        params['query'] = query

    if len(params) == 1:  # only 'number' was set
        logger.error("No search parameters provided to BigBookAPI")
        return {'books': []}

    for attempt in range(MAX_RETRIES):
        try:
            logger.info(f"Calling BigBookAPI attempt {attempt + 1}/{MAX_RETRIES} params: {params}")

            response = requests.get(
                BIGBOOK_API_URL,
                headers=headers,
                params=params,
                timeout=10
            )
            response.raise_for_status()
            data = response.json()

            logger.info(f"BigBookAPI returned {data.get('available', 0)} available books")
            return data

        except requests.exceptions.RequestException as e:
            logger.warning(f"API attempt {attempt + 1} failed: {str(e)}")

            if attempt == MAX_RETRIES - 1:
                logger.error("All BigBookAPI retry attempts exhausted")
                return {'books': []}

            time.sleep(2 ** attempt)  # Exponential backoff: 1s, 2s, 4s

    return {'books': []}


# For local testing
if __name__ == '__main__':
    test_cases = [
        # ISBN only
        {'requestId': 'req-1', 'isbn': '9780451524935', 'requesterEmail': 'user@example.com'},
        # Query only
        {'requestId': 'req-2', 'query': 'dystopian novels', 'requesterEmail': 'user@example.com'},
        # Authors only
        {'requestId': 'req-3', 'authors': 'J.K. Rowling', 'requesterEmail': 'user@example.com'},
        # All 3
        {'requestId': 'req-4', 'isbn': '9781781257654', 'authors': 'J.K. Rowling', 'query': 'wizards', 'requesterEmail': 'user@example.com'},
    ]

    for test in test_cases:
        event = {
            'Records': [{
                'messageId': test['requestId'],
                'receiptHandle': 'test-handle',
                'body': json.dumps({**test, 'requestDate': datetime.utcnow().isoformat()}),
                'eventSource': 'aws:sqs'
            }]
        }