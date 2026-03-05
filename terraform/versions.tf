terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Terraform backend blocks do not support variable interpolation.
  # The region and bucket name must be hardcoded here. Ensure the S3 bucket
  # and DynamoDB table are pre-provisioned in the same region before running
  # `terraform init`.
  backend "s3" {
    bucket         = "library-book-request-system-tfstate"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "library-book-request-system-tfstate-lock"
  }
}
