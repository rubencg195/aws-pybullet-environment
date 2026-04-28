data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# VPC to use (Name tag; see local.vpc_name in local.tf)
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}