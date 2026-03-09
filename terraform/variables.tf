variable "environment" {
  description = "Deployment environment (e.g. qa, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "producer_lambda_invoke_arn" {
  description = "Invoke ARN of the producer Lambda function integrated with API Gateway"
  type        = string
}

variable "producer_lambda_function_name" {
  description = "Name of the producer Lambda function for API Gateway invoke permission"
  type        = string
}
