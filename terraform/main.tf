resource "aws_secretsmanager_secret" "bigbook_api_key" {
  name = "${local.name_prefix}-bigbook-api-key"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bigbook-api-key"
  })
}