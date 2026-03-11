# Main API Gateway resource
resource "aws_api_gateway_rest_api" "book_requests_api" {
  name        = "${local.name_prefix}-book-requests-api"
  description = "API for submitting book requests to the library system"

  endpoint_configuration {
    types = ["REGIONAL"] # Use EDGE for CloudFront distribution, REGIONAL for direct access
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-book-requests-api"
    }
  )
}

# Create the /requests resource
resource "aws_api_gateway_resource" "requests" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id
  parent_id   = aws_api_gateway_rest_api.book_requests_api.root_resource_id
  path_part   = "requests"
}

# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "requests_options" {
  rest_api_id   = aws_api_gateway_rest_api.book_requests_api.id
  resource_id   = aws_api_gateway_resource.requests.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# OPTIONS method response
resource "aws_api_gateway_method_response" "requests_options_200" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration" "requests_post" {
  rest_api_id             = aws_api_gateway_rest_api.book_requests_api.id
  resource_id             = aws_api_gateway_resource.requests.id
  http_method             = aws_api_gateway_method.requests_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.producer.invoke_arn
  passthrough_behavior    = "WHEN_NO_MATCH"
  timeout_milliseconds    = 29000
}

# OPTIONS integration response
resource "aws_api_gateway_integration_response" "requests_options" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_options.http_method
  status_code = aws_api_gateway_method_response.requests_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration" "requests_options" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

# POST method — Fix #1: removed invalid request_parameters, Fix #2: linked model
resource "aws_api_gateway_method" "requests_post" {
  rest_api_id   = aws_api_gateway_rest_api.book_requests_api.id
  resource_id   = aws_api_gateway_resource.requests.id
  http_method   = "POST"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.body_validator.id
  api_key_required     = false

  # Fix #2: link the model so API Gateway actually validates against it
  request_models = {
    "application/json" = aws_api_gateway_model.request_model.name
  }
}


# Request validator
resource "aws_api_gateway_request_validator" "body_validator" {
  name                        = "${local.name_prefix}-body-validator"
  rest_api_id                 = aws_api_gateway_rest_api.book_requests_api.id
  validate_request_body       = true
  validate_request_parameters = false
}

# Model for request body validation — Fix #3: authors added, isbn not required
resource "aws_api_gateway_model" "request_model" {
  rest_api_id  = aws_api_gateway_rest_api.book_requests_api.id
  name         = "BookRequestModel"
  description  = "Schema for book request validation"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    type      = "object"
    required  = ["requesterEmail"] # Fix: only email is always required
    properties = {
      requesterEmail = {
        type        = "string"
        description = "Email of the person requesting the book"
      }
      isbn = {
        type        = "string"
        description = "ISBN-10 or ISBN-13 of the requested book"
        pattern     = "^[\\d-]{10,17}$"
      }
      authors = {
        type        = "string" # Fix: was missing entirely
        description = "Comma-separated author names or IDs"
      }
      query = {
        type        = "string"
        description = "Free-text search query"
      }
      notes = {
        type        = "string"
        description = "Additional notes about the request"
      }
    }
    additionalProperties = false
  })
}



resource "aws_api_gateway_method_response" "requests_post_202" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_post.http_method
  status_code = "202"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# POST method response for 400 Bad Request
resource "aws_api_gateway_method_response" "requests_post_400" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_post.http_method
  status_code = "400"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# POST method response for 500 Internal Error
resource "aws_api_gateway_method_response" "requests_post_500" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_post.http_method
  status_code = "500"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# Deployment resource (triggers on changes)
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.book_requests_api.id

  triggers = {
    # Redeploy when any of these change
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.requests.id,
      aws_api_gateway_method.requests_post.id,
      aws_api_gateway_method.requests_options.id,
      aws_api_gateway_integration.requests_post.id,
      aws_api_gateway_request_validator.body_validator.id,
      aws_api_gateway_model.request_model.schema,
    ]))
  }

  depends_on = [
    aws_api_gateway_method.requests_post,
    aws_api_gateway_method.requests_options,
    aws_api_gateway_integration.requests_options,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Development stage
resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.book_requests_api.id
  stage_name    = var.environment # "dev", "staging", "prod"

  description = "Book Request API - ${var.environment} environment"

  # Enable access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn

    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  # Enable X-Ray tracing
  xray_tracing_enabled = true

  # Stage variables
  variables = {
    environment = var.environment
    version     = "1.0.0"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-api-${var.environment}"
    }
  )
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${local.name_prefix}-book-requests-api"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-api-gateway-logs"
    }
  )
}

# API Gateway account settings (for CloudWatch logs)
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch]
}