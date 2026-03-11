# ==================================================
# DATA SOURCES
# ==================================================

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Archive the producer Lambda code
data "archive_file" "producer_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../src/producer"
  output_path = "${path.module}/../artifacts/producer-lambda.zip"
}

# Archive the consumer Lambda code
data "archive_file" "consumer_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../src/consumer"
  output_path = "${path.module}/../artifacts/consumer-lambda.zip"
}