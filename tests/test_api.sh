#!/bin/bash

API_URL="https://7i8z87ggxl.execute-api.us-east-2.amazonaws.com/qa/requests"
SQS_URL="https://sqs.us-east-2.amazonaws.com/854198083295/book-library-request-system-qa-requests"

echo "📤 Sending test request to API..."
RESPONSE=$(curl -s -X POST $API_URL \
  -H "Content-Type: application/json" \
  -d '{
    "isbn": "9780451524935",
    "requesterEmail": "test@example.com",
    "query": "1984 orwell",
    "notes": "Integration test"
  }')

echo "API Response: $RESPONSE"

# Extract requestId (requires jq)
REQUEST_ID=$(echo $RESPONSE | jq -r '.requestId')
echo "Request ID: $REQUEST_ID"

echo -e "\n⏳ Waiting for consumer to process..."
sleep 5

echo -e "\n📦 Checking SQS queue..."
aws sqs receive-message --queue-url $SQS_URL --region us-east-2

echo -e "\n📊 Checking DynamoDB for request $REQUEST_ID..."
aws dynamodb get-item \
  --table-name book-library-request-system-qa-book-requests \
  --key "{\"requestId\":{\"S\":\"$REQUEST_ID\"}}" \
  --region us-east-2