# -----------------------------------------------------------------------
# REST API
# -----------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "book_requests" {
  name        = "library-book-request-api-${var.environment}"
  description = "REST API for the Library Book Request System"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "library-book-request-api-${var.environment}"
  }
}

# -----------------------------------------------------------------------
# Request Validator
# -----------------------------------------------------------------------

resource "aws_api_gateway_request_validator" "body_validator" {
  rest_api_id                 = aws_api_gateway_rest_api.book_requests.id
  name                        = "validate-request-body"
  validate_request_body       = true
  validate_request_parameters = false
}

# -----------------------------------------------------------------------
# Request Model (JSON Schema for POST /requests)
# -----------------------------------------------------------------------

resource "aws_api_gateway_model" "book_request" {
  rest_api_id  = aws_api_gateway_rest_api.book_requests.id
  name         = "BookRequest"
  description  = "Schema for book request submissions"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "BookRequest"
    type      = "object"
    required  = ["title", "author", "requesterName"]
    properties = {
      title = {
        type = "string"
      }
      author = {
        type = "string"
      }
      requesterName = {
        type = "string"
      }
      isbn = {
        type = "string"
      }
      notes = {
        type = "string"
      }
    }
  })
}

# -----------------------------------------------------------------------
# Resource: /requests
# -----------------------------------------------------------------------

resource "aws_api_gateway_resource" "requests" {
  rest_api_id = aws_api_gateway_rest_api.book_requests.id
  parent_id   = aws_api_gateway_rest_api.book_requests.root_resource_id
  path_part   = "requests"
}

# -----------------------------------------------------------------------
# POST /requests Method
# -----------------------------------------------------------------------

resource "aws_api_gateway_method" "post_request" {
  rest_api_id          = aws_api_gateway_rest_api.book_requests.id
  resource_id          = aws_api_gateway_resource.requests.id
  http_method          = "POST"
  authorization        = "NONE"
  request_validator_id = aws_api_gateway_request_validator.body_validator.id

  request_models = {
    "application/json" = aws_api_gateway_model.book_request.name
  }
}

# -----------------------------------------------------------------------
# POST /requests Integration (Lambda Proxy)
# -----------------------------------------------------------------------

resource "aws_api_gateway_integration" "post_request_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.book_requests.id
  resource_id             = aws_api_gateway_resource.requests.id
  http_method             = aws_api_gateway_method.post_request.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.producer_lambda_invoke_arn
}

# -----------------------------------------------------------------------
# CORS – OPTIONS /requests (preflight)
# -----------------------------------------------------------------------

resource "aws_api_gateway_method" "options_request" {
  rest_api_id   = aws_api_gateway_rest_api.book_requests.id
  resource_id   = aws_api_gateway_resource.requests.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_request_mock" {
  rest_api_id = aws_api_gateway_rest_api.book_requests.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.options_request.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.book_requests.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.options_request.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.book_requests.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.options_request.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# -----------------------------------------------------------------------
# Deployment & Stage
# -----------------------------------------------------------------------

resource "aws_api_gateway_deployment" "book_requests" {
  rest_api_id = aws_api_gateway_rest_api.book_requests.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.requests.id,
      aws_api_gateway_method.post_request.id,
      aws_api_gateway_integration.post_request_lambda.id,
      aws_api_gateway_method.options_request.id,
      aws_api_gateway_integration.options_request_mock.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "book_requests" {
  deployment_id = aws_api_gateway_deployment.book_requests.id
  rest_api_id   = aws_api_gateway_rest_api.book_requests.id
  stage_name    = var.environment

  tags = {
    Name = "library-book-request-api-stage-${var.environment}"
  }
}

# -----------------------------------------------------------------------
# Lambda Permission – allow API Gateway to invoke the producer Lambda
# -----------------------------------------------------------------------

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.producer_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.book_requests.execution_arn}/*/${aws_api_gateway_method.post_request.http_method}${aws_api_gateway_resource.requests.path}"
}

# -----------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------

output "api_gateway_invoke_url" {
  description = "Base invoke URL of the API Gateway stage"
  value       = aws_api_gateway_stage.book_requests.invoke_url
}

output "api_gateway_rest_api_id" {
  description = "ID of the REST API"
  value       = aws_api_gateway_rest_api.book_requests.id
}

output "api_gateway_stage_name" {
  description = "Name of the deployed API stage"
  value       = aws_api_gateway_stage.book_requests.stage_name
}
