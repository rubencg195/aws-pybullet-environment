locals {
  project_name = "aws-pybullet-environment"

  # SSM String parameter written by Packer post-processor; OpenTofu reads it for module.ami_id.
  packer_golden_ami_ssm_parameter_name = "/${local.project_name}/golden-ami-id"

  # If non-null, skip Packer null_resource and SSM lookup; use this AMI for EC2.
  packer_ami_id_override = null

  # Subnet for Packer build instance (must reach internet). Same logic as ec2-instance module.
  packer_subnet_id = coalesce(
    local.ec2_subnet_id,
    length(data.aws_subnets.public_in_vpc.ids) > 0 ? sort(data.aws_subnets.public_in_vpc.ids)[0] : null,
  )

  # AWS CLI profile for Packer null_resource. Match provider "aws" profile in provider.tf.
  aws_cli_profile = "personal"

  # Must match the VPC’s Name tag in AWS (used by the ec2-instance module to select the VPC).
  vpc_name = "default-vpc"

  ec2_key_name      = null
  ec2_instance_type = "g5.xlarge"
  # Optional subnet id; if null, first subnet id (sorted) whose Name matches *public* for this VPC (see module data.aws_subnets.filtered).
  ec2_subnet_id = null

  # Inbound CIDRs for SSH (22) and NICE DCV (8443) on the PyBullet host.
  # If empty, apply falls back to 0.0.0.0/0 (any IPv4). That is only for quick
  # dev: it exposes admin ports to the whole internet. For anything non-throwaway,
  # set to your public IP/32 (or a small range). See README "Security: instance ingress".
  allowed_ingress_cidrs = []

  sg_ingress_cidrs = length(local.allowed_ingress_cidrs) > 0 ? local.allowed_ingress_cidrs : ["0.0.0.0/0"]
}
