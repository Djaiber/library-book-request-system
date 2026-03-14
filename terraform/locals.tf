locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    Owner       = "jaiberdiaz"
    ManagedBy   = "Terraform"
    CostCenter  = "my-cost-center"
  }
}
