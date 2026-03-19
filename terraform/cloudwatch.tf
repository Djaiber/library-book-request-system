# -----------------------------------------------------------------------
# Variables — Monitoring & Alerting
# -----------------------------------------------------------------------

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "sqs_queue_depth_threshold" {
  description = "Threshold for the number of visible messages in the SQS queue before triggering an alarm"
  type        = number
  default     = 100
}

variable "sqs_message_age_threshold" {
  description = "Threshold in seconds for the age of the oldest message in the SQS queue before triggering an alarm"
  type        = number
  default     = 3600
}

# -----------------------------------------------------------------------
# SNS Topic for CloudWatch Alarm Notifications
# -----------------------------------------------------------------------

resource "aws_sns_topic" "cloudwatch_alarms" {
  name = "${var.project_name}-cloudwatch-alarms-${var.environment}"

  tags = {
    Name        = "${var.project_name}-cloudwatch-alarms-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cloudwatch_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# -----------------------------------------------------------------------
# Lambda Alarms — Producer
# -----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "producer_errors" {
  alarm_name          = "${var.project_name}-producer-errors-${var.environment}"
  alarm_description   = "Producer Lambda function error rate exceeded threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.producer.function_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-producer-errors-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "producer_duration" {
  alarm_name          = "${var.project_name}-producer-duration-${var.environment}"
  alarm_description   = "Producer Lambda function duration exceeded threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.producer.function_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-producer-duration-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "producer_throttles" {
  alarm_name          = "${var.project_name}-producer-throttles-${var.environment}"
  alarm_description   = "Producer Lambda function is being throttled"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.producer.function_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-producer-throttles-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------
# Lambda Alarms — Consumer
# -----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "consumer_errors" {
  alarm_name          = "${var.project_name}-consumer-errors-${var.environment}"
  alarm_description   = "Consumer Lambda function error rate exceeded threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.consumer.function_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-consumer-errors-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "consumer_duration" {
  alarm_name          = "${var.project_name}-consumer-duration-${var.environment}"
  alarm_description   = "Consumer Lambda function duration exceeded threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.consumer.function_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-consumer-duration-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "consumer_throttles" {
  alarm_name          = "${var.project_name}-consumer-throttles-${var.environment}"
  alarm_description   = "Consumer Lambda function is being throttled"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.consumer.function_name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-consumer-throttles-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------
# SQS Queue Alarms
# -----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${var.project_name}-sqs-queue-depth-${var.environment}"
  alarm_description   = "SQS queue has too many messages waiting to be processed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = var.sqs_queue_depth_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.book_request.name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-sqs-queue-depth-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_message_age" {
  alarm_name          = "${var.project_name}-sqs-message-age-${var.environment}"
  alarm_description   = "SQS oldest message age exceeded threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.sqs_message_age_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.book_request.name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-sqs-message-age-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  alarm_name          = "${var.project_name}-sqs-dlq-messages-${var.environment}"
  alarm_description   = "Dead letter queue has received messages — indicates processing failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.book_request_dlq.name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-sqs-dlq-messages-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------
# DynamoDB Throttling Alarms
# -----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dynamodb_read_throttles" {
  alarm_name          = "${var.project_name}-dynamodb-read-throttles-${var.environment}"
  alarm_description   = "DynamoDB read requests are being throttled"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.books_request.name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-dynamodb-read-throttles-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttles" {
  alarm_name          = "${var.project_name}-dynamodb-write-throttles-${var.environment}"
  alarm_description   = "DynamoDB write requests are being throttled"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.books_request.name
  }

  alarm_actions = [aws_sns_topic.cloudwatch_alarms.arn]

  tags = {
    Name        = "${var.project_name}-dynamodb-write-throttles-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------
# CloudWatch Dashboard
# -----------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      # --- Lambda Metrics ---
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Lambda Functions"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda Invocations"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.producer.function_name, { label = "Producer" }],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.consumer.function_name, { label = "Consumer" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda Errors"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.producer.function_name, { label = "Producer" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.consumer.function_name, { label = "Consumer" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda Duration (ms)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Average"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.producer.function_name, { label = "Producer" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.consumer.function_name, { label = "Consumer" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Throttles"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.producer.function_name, { label = "Producer" }],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.consumer.function_name, { label = "Consumer" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Concurrent Executions"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Maximum"
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.producer.function_name, { label = "Producer" }],
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.consumer.function_name, { label = "Consumer" }]
          ]
        }
      },
      # --- SQS Metrics ---
      {
        type   = "text"
        x      = 0
        y      = 13
        width  = 24
        height = 1
        properties = {
          markdown = "# SQS Queues"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "Messages Visible (Queue Depth)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.book_request.name, { label = "Main Queue" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.book_request_dlq.name, { label = "DLQ" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "Messages Sent / Received"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", aws_sqs_queue.book_request.name, { label = "Sent" }],
            ["AWS/SQS", "NumberOfMessagesReceived", "QueueName", aws_sqs_queue.book_request.name, { label = "Received" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", aws_sqs_queue.book_request.name, { label = "Deleted" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "Oldest Message Age (seconds)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Maximum"
          metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", aws_sqs_queue.book_request.name, { label = "Main Queue" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", aws_sqs_queue.book_request_dlq.name, { label = "DLQ" }]
          ]
        }
      },
      # --- DynamoDB Metrics ---
      {
        type   = "text"
        x      = 0
        y      = 20
        width  = 24
        height = 1
        properties = {
          markdown = "# DynamoDB"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 21
        width  = 12
        height = 6
        properties = {
          title   = "DynamoDB Read/Write Capacity"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.books_request.name, { label = "Read Capacity" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.books_request.name, { label = "Write Capacity" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 21
        width  = 12
        height = 6
        properties = {
          title   = "DynamoDB Throttle Events"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/DynamoDB", "ReadThrottleEvents", "TableName", aws_dynamodb_table.books_request.name, { label = "Read Throttles" }],
            ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", aws_dynamodb_table.books_request.name, { label = "Write Throttles" }]
          ]
        }
      },
      # --- API Gateway Metrics ---
      {
        type   = "text"
        x      = 0
        y      = 27
        width  = 24
        height = 1
        properties = {
          markdown = "# API Gateway"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 28
        width  = 8
        height = 6
        properties = {
          title   = "API Request Count"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.book_requests.name, { label = "Requests" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 28
        width  = 8
        height = 6
        properties = {
          title   = "API Latency (ms)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Average"
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiName", aws_api_gateway_rest_api.book_requests.name, { label = "Latency" }],
            ["AWS/ApiGateway", "IntegrationLatency", "ApiName", aws_api_gateway_rest_api.book_requests.name, { label = "Integration Latency" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 28
        width  = 8
        height = 6
        properties = {
          title   = "API Errors"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/ApiGateway", "4XXError", "ApiName", aws_api_gateway_rest_api.book_requests.name, { label = "4XX Errors" }],
            ["AWS/ApiGateway", "5XXError", "ApiName", aws_api_gateway_rest_api.book_requests.name, { label = "5XX Errors" }]
          ]
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarm notifications"
  value       = aws_sns_topic.cloudwatch_alarms.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
