variable "environment" {
  description = "Deployment environment (e.g. qa, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "sqs_visibility_timeout" {
  description = "Visibility timeout for the main SQS queue in seconds"
  type        = number
  default     = 30
}

variable "sqs_message_retention" {
  description = "Message retention period for the main SQS queue in seconds (default 4 days)"
  type        = number
  default     = 345600
}

variable "sqs_dlq_message_retention" {
  description = "Message retention period for the DLQ in seconds (default 14 days)"
  type        = number
  default     = 1209600
}

variable "sqs_max_receive_count" {
  description = "Number of times a message can be received before being sent to the DLQ"
  type        = number
  default     = 3
}
