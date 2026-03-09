# -----------------------------------------------------------------------
# Stage-Level Method Settings (default throttling for all methods)
# -----------------------------------------------------------------------

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = var.api_gateway_rest_api_id
  stage_name  = var.api_gateway_stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
    metrics_enabled        = true
    logging_level          = "INFO"
  }
}

# -----------------------------------------------------------------------
# Usage Plan (throttle + quota limits for API key consumers)
# -----------------------------------------------------------------------

resource "aws_api_gateway_usage_plan" "book_requests" {
  name        = "library-book-request-usage-plan-${var.environment}"
  description = "Usage plan with throttle and quota limits for the Library Book Request API"

  api_stages {
    api_id = var.api_gateway_rest_api_id
    stage  = var.api_gateway_stage_name
  }

  throttle_settings {
    burst_limit = 25
    rate_limit  = 50
  }

  quota_settings {
    limit  = 10000
    period = "DAY"
  }

  tags = {
    Name = "library-book-request-usage-plan-${var.environment}"
  }
}

# -----------------------------------------------------------------------
# API Key
# -----------------------------------------------------------------------

resource "aws_api_gateway_api_key" "book_requests" {
  name    = "library-book-request-api-key-${var.environment}"
  enabled = true

  tags = {
    Name = "library-book-request-api-key-${var.environment}"
  }
}

# -----------------------------------------------------------------------
# Associate API Key with Usage Plan
# -----------------------------------------------------------------------

resource "aws_api_gateway_usage_plan_key" "book_requests" {
  key_id        = aws_api_gateway_api_key.book_requests.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.book_requests.id
}
