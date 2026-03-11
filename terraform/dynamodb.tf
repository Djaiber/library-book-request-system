resource "aws_dynamodb_table" "book_requests" {
  name         = "${local.name_prefix}-book-requests"
  billing_mode = "PAY_PER_REQUEST"

  # Primary key
  hash_key = "requestId"

  # Only declare attributes used in keys or GSIs
  attribute {
    name = "requestId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  attribute {
    name = "requesterEmail"
    type = "S"
  }

  attribute {
    name = "isbn"
    type = "S"
  }

  attribute {
    name = "bookId"
    type = "S"
  }

  # GSI: librarians filter by status + date
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # GSI: users check their own requests
  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "requesterEmail"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # GSI: avoid duplicate ISBN requests
  global_secondary_index {
    name            = "IsbnIndex"
    hash_key        = "isbn"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # GSI: lookup by BigBookAPI book id
  global_secondary_index {
    name            = "BookIdIndex"
    hash_key        = "bookId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = var.environment == "prod" ? true : false
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-book-requests"
    }
  )
}