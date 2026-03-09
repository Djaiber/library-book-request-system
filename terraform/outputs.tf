output "book_request_queue_arn" {
  description = "ARN of the main book request SQS queue"
  value       = aws_sqs_queue.book_request.arn
}

output "book_request_queue_url" {
  description = "URL of the main book request SQS queue"
  value       = aws_sqs_queue.book_request.url
}

output "book_request_dlq_arn" {
  description = "ARN of the book request dead letter queue"
  value       = aws_sqs_queue.book_request_dlq.arn
}

output "book_request_dlq_url" {
  description = "URL of the book request dead letter queue"
  value       = aws_sqs_queue.book_request_dlq.url
}
