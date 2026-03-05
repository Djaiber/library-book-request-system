provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "library-book-request-system"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
