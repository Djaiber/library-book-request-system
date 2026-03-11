variable "environment" {
  description = "The environment for the deployment"
  type        = string
}
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "use_separate_lambda_roles" {
  description = "Whether to create separate IAM roles for producer and consumer"
  type        = bool
  default     = false
}

# Lambda configuration
variable "producer_memory_size" {
  description = "Memory size for producer Lambda in MB"
  type        = number
  default     = 128
}

variable "producer_timeout" {
  description = "Timeout for producer Lambda in seconds"
  type        = number
  default     = 10
}

variable "log_level" {
  description = "Logging level (INFO, DEBUG, ERROR)"
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "Days to retain CloudWatch logs"
  type        = number
  default     = 30
}

# Consumer Lambda configuration
variable "consumer_memory_size" {
  description = "Memory size for consumer Lambda in MB"
  type        = number
  default     = 256
}

variable "consumer_timeout" {
  description = "Timeout for consumer Lambda in seconds"
  type        = number
  default     = 30
}

variable "consumer_batch_size" {
  description = "Number of SQS messages to process in each batch (max 10)"
  type        = number
  default     = 5
}

variable "consumer_batching_window" {
  description = "Maximum batching window in seconds (0-300)"
  type        = number
  default     = 0
}

variable "consumer_max_concurrency" {
  description = "Maximum concurrent Lambda instances for SQS trigger"
  type        = number
  default     = 5
}

variable "consumer_max_retries" {
  description = "Maximum number of retries for API calls"
  type        = number
  default     = 3
}

# BigBookAPI configuration
variable "bigbook_api_key" {
  description = "API key for BigBookAPI"
  type        = string
  sensitive   = true
}

variable "bigbook_api_url" {
  description = "BigBookAPI endpoint URL"
  type        = string
  default     = "https://api.bigbookapi.com/search-books"
}

# SNS for alerts
variable "sns_topic_arn" {
  description = "SNS topic ARN for alarms (optional)"
  type        = string
  default     = ""
}