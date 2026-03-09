variable "environment" {
  description = "Deployment environment (e.g. qa, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}
