# Lambda endpoints
output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.name
}
# SQS endpoints
output "sqs_queue_url" {
  description = "URL of the main SQS queue"
  value       = aws_sqs_queue.book_requests_queue.url
}

output "sqs_queue_arn" {
  description = "ARN of the main SQS queue"
  value       = aws_sqs_queue.book_requests_queue.arn
}

output "sqs_dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.book_requests_dlq.url
}

output "sqs_dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.book_requests_dlq.arn
}

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.book_requests_api.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}/requests"
}

output "api_id" {
  description = "API Gateway ID"
  value       = aws_api_gateway_rest_api.book_requests_api.id
}