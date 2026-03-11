# DLQ for messages that fail processing
resource "aws_sqs_queue" "book_requests_dlq" {
  name = "${local.name_prefix}-requests-dlq"

  # Message retention: 14 days (maximum)
  message_retention_seconds = 1209600

  # Visibility timeout: 30 seconds (matching consumer lambda timeout)
  visibility_timeout_seconds = 30

  # No redrive policy for DLQ itself
  # DLQ doesn't need a DLQ (but could be configured if needed)

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-requests-dlq"
      Type = "dead-letter-queue"
    }
  )
}

# main SQS queue for book requests
resource "aws_sqs_queue" "book_requests_queue" {
  name = "${local.name_prefix}-requests"

  # Message retention: 4 days (balance between recovery and freshness)
  message_retention_seconds = 345600

  # Visibility timeout: 30 seconds (matches consumer Lambda timeout)
  # Messages are hidden while being processed
  visibility_timeout_seconds = 30

  # Delivery delay: 0 seconds (messages available immediately)
  delay_seconds = 0

  # Maximum message size: 256KB (enough for book requests)
  max_message_size = 262144

  # Receive message wait time: 0 seconds (no long polling)
  receive_wait_time_seconds = 0

  # Enable content-based deduplication (not using FIFO, so false)
  content_based_deduplication = false

  # Redrive policy: send failed messages to DLQ after 3 attempts
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.book_requests_dlq.arn
    maxReceiveCount     = 3 # Try 3 times before sending to DLQ
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-requests"
      Type = "main-queue"
    }
  )
}

# Alarm for messages in DLQ (indicating processing failures)
resource "aws_cloudwatch_metric_alarm" "dlq_messages_alarm" {
  alarm_name          = "${local.name_prefix}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when messages appear in DLQ"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    QueueName = aws_sqs_queue.book_requests_dlq.name
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-dlq-alarm"
    }
  )
}

# Alarm for queue backlog (messages waiting too long)
resource "aws_cloudwatch_metric_alarm" "queue_backlog_alarm" {
  alarm_name          = "${local.name_prefix}-queue-backlog"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300 # 5 minutes
  statistic           = "Maximum"
  threshold           = 600 # 10 minutes
  alarm_description   = "Alarm when messages are stuck in queue for >10 minutes"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    QueueName = aws_sqs_queue.book_requests_queue.name
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-backlog-alarm"
    }
  )
}