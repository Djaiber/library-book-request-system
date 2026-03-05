variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "sqs_queue_arns" {
  description = "List of SQS queue ARNs the Lambda functions are allowed to access"
  type        = list(string)
  default     = []
}

variable "dynamodb_table_arns" {
  description = "List of DynamoDB table ARNs the Lambda functions are allowed to access"
  type        = list(string)
  default     = []
}
