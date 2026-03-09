resource "aws_dynamodb_table" "books_request" {
  name         = "BooksRequest-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "requestId"

  attribute {
    name = "requestId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Name        = "BooksRequest-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
