data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Dead Letter Queue (DLQ)
# Captures messages that fail processing after max_receive_count attempts
# -----------------------------------------------------------------------------
resource "aws_sqs_queue" "book_request_dlq" {
  name                      = "library-book-request-dlq-${var.environment}"
  message_retention_seconds = var.sqs_dlq_message_retention

  tags = {
    Name = "library-book-request-dlq-${var.environment}"
  }
}

# -----------------------------------------------------------------------------
# Main SQS Queue
# Receives book request messages for Lambda processing
# -----------------------------------------------------------------------------
resource "aws_sqs_queue" "book_request" {
  name                       = "library-book-request-queue-${var.environment}"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.book_request_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = {
    Name = "library-book-request-queue-${var.environment}"
  }
}

# -----------------------------------------------------------------------------
# Queue Policy — grants Lambda service access to the main queue
# -----------------------------------------------------------------------------
resource "aws_sqs_queue_policy" "book_request_policy" {
  queue_url = aws_sqs_queue.book_request.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLambdaAccess"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.book_request.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
