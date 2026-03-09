provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "library-book-request-system"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
