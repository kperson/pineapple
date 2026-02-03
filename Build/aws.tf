terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# AWS Provider uses the standard credential chain:
# 1. Environment variables (AWS_PROFILE, AWS_REGION, AWS_ACCESS_KEY_ID, etc.)
# 2. Shared credentials file (~/.aws/credentials and ~/.aws/config)
# 3. EC2 instance metadata / ECS task role
#
# To use a specific profile: export AWS_PROFILE=your-profile
# To use a specific region: Set var.aws_region or export AWS_REGION=your-region
provider "aws" {
  region = var.aws_region
}