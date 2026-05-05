data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# VPC to use (Name tag; see local.vpc_name in local.tf)
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

# Same subnet rule as ec2-instance module: public by Name tag, scoped to vpc_name.
data "aws_subnets" "public_in_vpc" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

# Auto-detect the apply host's public IP for security group ingress.
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}