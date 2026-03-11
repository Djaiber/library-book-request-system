# Producer Lambda function
resource "aws_lambda_function" "producer" {
  filename         = data.archive_file.producer_lambda.output_path
  function_name    = "${local.name_prefix}-producer"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.producer_lambda.output_base64sha256

  # Memory: 128MB (sufficient for simple validation and SQS calls)
  memory_size = var.producer_memory_size

  # Timeout: 10 seconds (API Gateway timeout is 29s, so 10s is safe)
  timeout = var.producer_timeout

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.book_requests_queue.url
      ENVIRONMENT   = var.environment
      LOG_LEVEL     = var.log_level
    }
  }

  # Enable Lambda Insights for enhanced monitoring
  tracing_config {
    mode = "Active"
  }

  tags = merge(
    local.common_tags,
    {
      Name     = "${local.name_prefix}-producer"
      Function = "producer"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy_attachment.lambda_sqs_producer,
    aws_cloudwatch_log_group.producer_lambda
  ]
}

resource "aws_cloudwatch_log_group" "producer_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-producer"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-producer-logs"
    }
  )
}

resource "aws_lambda_permission" "allow_api_gateway_producer" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"

  # Fix: use REST API execution_arn, not apigatewayv2
  source_arn = "${aws_api_gateway_rest_api.book_requests_api.execution_arn}/*/*"
}

# Consumer Lambda function
resource "aws_lambda_function" "consumer" {
  filename         = data.archive_file.consumer_lambda.output_path
  function_name    = "${local.name_prefix}-consumer"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.consumer_lambda.output_base64sha256

  # Memory: 256MB (for API calls and data processing)
  memory_size = var.consumer_memory_size

  # Timeout: 30 seconds (API calls may take time)
  timeout = var.consumer_timeout

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.book_requests.name
      SECRET_ARN          = aws_secretsmanager_secret.bigbook_api_key.arn # For secure API key storage
      BIGBOOK_API_URL     = var.bigbook_api_url
      ENVIRONMENT         = var.environment
      LOG_LEVEL           = var.log_level
      MAX_RETRIES         = var.consumer_max_retries
    }
  }

  # Enable Lambda Insights for enhanced monitoring
  tracing_config {
    mode = "Active"
  }

  tags = merge(
    local.common_tags,
    {
      Name     = "${local.name_prefix}-consumer"
      Function = "consumer"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy_attachment.lambda_sqs_consumer,
    aws_iam_role_policy_attachment.lambda_dynamodb,
    aws_cloudwatch_log_group.consumer_lambda
  ]
}

resource "aws_cloudwatch_log_group" "consumer_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-consumer"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-consumer-logs"
    }
  )
}


# This allows the consumer Lambda to be triggered by SQS messages from the main queue
resource "aws_lambda_event_source_mapping" "consumer_sqs_trigger" {
  event_source_arn = aws_sqs_queue.book_requests_queue.arn
  function_name    = aws_lambda_function.consumer.arn

  # Batch processing configuration
  batch_size                         = var.consumer_batch_size
  maximum_batching_window_in_seconds = var.consumer_batching_window

  # Scaling configuration
  scaling_config {
    maximum_concurrency = var.consumer_max_concurrency
  }

  # Error handling - report individual item failures
  function_response_types = ["ReportBatchItemFailures"]

  # Enable the mapping
  enabled = true

  depends_on = [
    aws_lambda_function.consumer,
    aws_sqs_queue.book_requests_queue
  ]
}

resource "aws_lambda_permission" "allow_sqs_consumer" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.consumer.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.book_requests_queue.arn
}

# Alert when messages end up in DLQ
resource "aws_cloudwatch_metric_alarm" "consumer_dlq_alarm" {
  alarm_name          = "${local.name_prefix}-consumer-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in DLQ indicate consumer processing failures"

  dimensions = {
    QueueName = aws_sqs_queue.book_requests_dlq.name
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-consumer-dlq-alarm"
    }
  )
}

