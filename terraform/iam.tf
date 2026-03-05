# -----------------------------------------------------------------------
# Current AWS account data
# -----------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------
# IAM Role for Lambda Functions
# -----------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  name               = "library-book-request-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "library-book-request-lambda-role-${var.environment}"
  }
}

# -----------------------------------------------------------------------
# SQS Access Policy (least privilege)
# -----------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_sqs" {
  statement {
    sid    = "AllowSQSAccess"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    # When no specific queues are provided the policy defaults to a
    # placeholder that must be replaced before deployment.  Providing
    # var.sqs_queue_arns at runtime scopes the policy to exact resources.
    resources = length(var.sqs_queue_arns) > 0 ? var.sqs_queue_arns : ["arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:library-book-request-*"]
  }
}

resource "aws_iam_policy" "lambda_sqs" {
  name        = "library-book-request-lambda-sqs-${var.environment}"
  description = "Least-privilege SQS access for the library book request Lambda functions"
  policy      = data.aws_iam_policy_document.lambda_sqs.json

  tags = {
    Name = "library-book-request-lambda-sqs-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_sqs.arn
}

# -----------------------------------------------------------------------
# DynamoDB Access Policy (least privilege)
# -----------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    sid    = "AllowDynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:DescribeTable",
    ]
    resources = length(var.dynamodb_table_arns) > 0 ? concat(
      var.dynamodb_table_arns,
      [for arn in var.dynamodb_table_arns : "${arn}/index/*"]
    ) : ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/library-book-request-*"]
  }
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name        = "library-book-request-lambda-dynamodb-${var.environment}"
  description = "Least-privilege DynamoDB access for the library book request Lambda functions"
  policy      = data.aws_iam_policy_document.lambda_dynamodb.json

  tags = {
    Name = "library-book-request-lambda-dynamodb-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# -----------------------------------------------------------------------
# CloudWatch Logs Policy (least privilege)
# -----------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_cloudwatch_logs" {
  statement {
    sid    = "AllowCloudWatchLogsAccess"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/library-book-request-*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/library-book-request-*:log-stream:*",
    ]
  }
}

resource "aws_iam_policy" "lambda_cloudwatch_logs" {
  name        = "library-book-request-lambda-cloudwatch-logs-${var.environment}"
  description = "Least-privilege CloudWatch Logs access for the library book request Lambda functions"
  policy      = data.aws_iam_policy_document.lambda_cloudwatch_logs.json

  tags = {
    Name = "library-book-request-lambda-cloudwatch-logs-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_logs.arn
}

# -----------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role assumed by Lambda functions"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role assumed by Lambda functions"
  value       = aws_iam_role.lambda_execution.name
}

output "lambda_sqs_policy_arn" {
  description = "ARN of the IAM policy granting SQS access to Lambda functions"
  value       = aws_iam_policy.lambda_sqs.arn
}

output "lambda_dynamodb_policy_arn" {
  description = "ARN of the IAM policy granting DynamoDB access to Lambda functions"
  value       = aws_iam_policy.lambda_dynamodb.arn
}

output "lambda_cloudwatch_logs_policy_arn" {
  description = "ARN of the IAM policy granting CloudWatch Logs access to Lambda functions"
  value       = aws_iam_policy.lambda_cloudwatch_logs.arn
}
