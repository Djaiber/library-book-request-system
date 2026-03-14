resource "aws_secretsmanager_secret" "bigbook_api_key" {
  name = "${local.name_prefix}-bigbook-api-key"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bigbook-api-key"
  })
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