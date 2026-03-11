# Trust policy document - allows Lambda service to assume this role
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}
# Main Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "IAM role for Lambda functions in book request system"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lambda-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${local.name_prefix}-lambda-secrets-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.bigbook_api_key.arn
      }
    ]
  })
}

# Policy document for CloudWatch Logs access
data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    ]
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }
}

# Create CloudWatch Logs policy
resource "aws_iam_policy" "cloudwatch_logs" {
  name        = "${local.name_prefix}-lambda-logs"
  description = "Allows Lambda to create logs in CloudWatch"
  policy      = data.aws_iam_policy_document.cloudwatch_logs.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lambda-logs"
    }
  )
}

# Policy document for SQS access (Producer)
data "aws_iam_policy_document" "sqs_producer" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes"
    ]
    resources = [
      aws_sqs_queue.book_requests_queue.arn,
      aws_sqs_queue.book_requests_dlq.arn
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }
}

# Create SQS Producer policy
resource "aws_iam_policy" "sqs_producer" {
  name        = "${local.name_prefix}-sqs-producer"
  description = "Allows Lambda to send messages to SQS queue"
  policy      = data.aws_iam_policy_document.sqs_producer.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-sqs-producer"
    }
  )
}

# Policy document for SQS Consumer access
data "aws_iam_policy_document" "sqs_consumer" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [
      aws_sqs_queue.book_requests_queue.arn,
      aws_sqs_queue.book_requests_dlq.arn
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }
}

# Create SQS Consumer policy
resource "aws_iam_policy" "sqs_consumer" {
  name        = "${local.name_prefix}-sqs-consumer"
  description = "Allows Lambda to receive/delete messages from SQS queue"
  policy      = data.aws_iam_policy_document.sqs_consumer.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-sqs-consumer"
    }
  )
}

# Policy for main sqs queue
data "aws_iam_policy_document" "main_queue_policy" {
  # Allow Lambda functions from same account to access queue
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]

    resources = [aws_sqs_queue.book_requests_queue.arn]
  }
}

# Policy for DLQ
data "aws_iam_policy_document" "dlq_policy" {
  # Allow Lambda/account to access DLQ
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [aws_sqs_queue.book_requests_dlq.arn] # single resource
  }

  # Allow SQS service to redrive messages into DLQ
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sqs.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.book_requests_dlq.arn] # single resource
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sqs_queue.book_requests_queue.arn]
    }
  }
}

# Attach policy to main queue
resource "aws_sqs_queue_policy" "main_queue_policy" {
  queue_url = aws_sqs_queue.book_requests_queue.id
  policy    = data.aws_iam_policy_document.main_queue_policy.json
}

# Attach policy to DLQ
resource "aws_sqs_queue_policy" "dlq_policy" {
  queue_url = aws_sqs_queue.book_requests_dlq.id
  policy    = data.aws_iam_policy_document.dlq_policy.json
}

# Policy document for DynamoDB access
data "aws_iam_policy_document" "dynamodb" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:BatchWriteItem"
    ]
    resources = [
      aws_dynamodb_table.book_requests.arn,
      "${aws_dynamodb_table.book_requests.arn}/index/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }

  # Conditional access for DynamoDB streams (if needed)
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams"
    ]
    resources = [
      "${aws_dynamodb_table.book_requests.arn}/stream/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }
}

# Create DynamoDB policy
resource "aws_iam_policy" "dynamodb" {
  name        = "${local.name_prefix}-dynamodb"
  description = "Allows Lambda to interact with DynamoDB table"
  policy      = data.aws_iam_policy_document.dynamodb.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-dynamodb"
    }
  )
}

# Attach CloudWatch Logs policy to role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

# Attach SQS Producer policy to role (for producer Lambda)
resource "aws_iam_role_policy_attachment" "lambda_sqs_producer" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sqs_producer.arn
}

# Attach SQS Consumer policy to role (for consumer Lambda)
resource "aws_iam_role_policy_attachment" "lambda_sqs_consumer" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sqs_consumer.arn
}

# Attach DynamoDB policy to role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb.arn
}

# OPTIONAL: Separate Roles for Producer/Consumer
# Producer-specific role (only needs SQS write + logs)
resource "aws_iam_role" "producer_lambda_role" {
  count = var.use_separate_lambda_roles ? 1 : 0

  name               = "${local.name_prefix}-producer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "IAM role for Producer Lambda function"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-producer-role"
    }
  )
}

# Consumer-specific role (needs SQS read + DynamoDB + logs)
resource "aws_iam_role" "consumer_lambda_role" {
  count = var.use_separate_lambda_roles ? 1 : 0

  name               = "${local.name_prefix}-consumer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "IAM role for Consumer Lambda function"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-consumer-role"
    }
  )
}

# IAM role for API Gateway to write logs
resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${local.name_prefix}-api-gateway-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-api-gateway-cloudwatch"
    }
  )
}

# IAM policy for API Gateway CloudWatch logs
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}