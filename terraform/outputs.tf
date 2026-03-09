# -----------------------------------------------------------------------
# API Gateway Outputs
# -----------------------------------------------------------------------

output "api_gateway_invoke_url" {
  description = "Base invoke URL of the API Gateway stage"
  value       = aws_api_gateway_stage.book_requests.invoke_url
}

# -----------------------------------------------------------------------
# SQS Queue Outputs
# -----------------------------------------------------------------------

output "sqs_queue_url" {
  description = "URL of the main book request SQS queue"
  value       = aws_sqs_queue.book_request.url
}

output "sqs_dlq_url" {
  description = "URL of the book request dead letter queue"
  value       = aws_sqs_queue.book_request_dlq.url
}

# -----------------------------------------------------------------------
# DynamoDB Outputs
# -----------------------------------------------------------------------

output "dynamodb_table_name" {
  description = "Name of the DynamoDB book requests table"
  value       = aws_dynamodb_table.books_request.name
}

# -----------------------------------------------------------------------
# Lambda Function Outputs
# -----------------------------------------------------------------------

output "producer_lambda_function_name" {
  description = "Name of the producer Lambda function"
  value       = aws_lambda_function.producer.function_name
}

output "consumer_lambda_function_name" {
  description = "Name of the consumer Lambda function"
  value       = aws_lambda_function.consumer.function_name
}
