variable "environment" {
  description = "Deployment environment (e.g. qa, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-2"
}

variable "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API for usage plan association"
  type        = string
}

variable "api_gateway_stage_name" {
  description = "Name of the API Gateway stage for usage plan association"
  type        = string
}
