terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # ---------------------------------------------------------------------------
  # Backend: replace placeholders after the S3 state bucket (and lock) exist.
  # ---------------------------------------------------------------------------
  backend "s3" {
    bucket  = "terraform-state-us-east-1-176843580427"
    key     = "aws-pybullet-environment/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "personal"
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "personal"
}
