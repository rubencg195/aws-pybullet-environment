data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# All subnets in the VPC (fallback when the VPC has no "public" subnets in the sense below)
data "aws_subnets" "this" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Public subnets: required for the default pick so the instance can reach the internet
# (SSM, patches) unless you use a NAT gateway or SSM/EC2 VPC interface endpoints.
# The SSM agent uses HTTPS to regional endpoints; a private-only subnet with no NAT
# and no endpoints = Fleet Manager "Offline."
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnet" "selected" {
  id = local.subnet_id
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
