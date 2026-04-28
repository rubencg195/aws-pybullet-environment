locals {
  project_name = "aws-pybullet-environment"

  # Must match the VPC’s Name tag in AWS (used by the ec2-instance module to select the VPC).
  vpc_name = "default-vpc"

  ec2_key_name        = null
  ec2_instance_type   = "g4dn.2xlarge"
  # Optional subnet id; if null, first subnet id (sorted) whose Name matches *public* for this VPC (see module data.aws_subnets.filtered).
  ec2_subnet_id = null

  # Inbound CIDRs for SSH (22) and NICE DCV (8443) on the PyBullet host.
  # If empty, Terraform falls back to 0.0.0.0/0 (any IPv4). That is only for quick
  # dev: it exposes admin ports to the whole internet. For anything non-throwaway,
  # set to your public IP/32 (or a small range). See README "Security: instance ingress".
  allowed_ingress_cidrs = []

  sg_ingress_cidrs = length(local.allowed_ingress_cidrs) > 0 ? local.allowed_ingress_cidrs : ["0.0.0.0/0"]
}
