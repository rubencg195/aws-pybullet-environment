output "aws_region" {
  description = "Region for this stack (SSM, CLI, DCV in browser)"
  value       = data.aws_region.current.id
}

output "pybullet_golden_ami_id" {
  description = "AMI id used for the PyBullet host (SSM parameter or packer_ami_id_override)"
  value       = local.packer_ami_id_override != null ? local.packer_ami_id_override : data.aws_ssm_parameter.golden_ami_id[0].value
}

output "pybullet_golden_ami_ssm_parameter_name" {
  description = "SSM parameter name holding the golden AMI id (written by Packer)"
  value       = local.packer_golden_ami_ssm_parameter_name
}

output "pybullet_host_instance_id" {
  description = "PyBullet host instance id (SSM session target)"
  value       = module.pybullet_host.instance_id
}

output "pybullet_host_subnet_id" {
  description = "Subnet the instance uses (verify in EC2: it should be public for SSM without NAT/endpoints, or have NAT+routes)"
  value       = module.pybullet_host.subnet_id
}
output "pybullet_host_public_ip" {
  description = "Public IP when the subnet assigns one"
  value       = module.pybullet_host.public_ip
}

output "pybullet_host_dcv_url" {
  description = "NICE/Amazon DCV web client URL (click in OpenTofu Cloud / some terminals when shown as a link)"
  value       = module.pybullet_host.public_ip != null ? "https://${module.pybullet_host.public_ip}:8443" : null
}

output "pybullet_host_private_ip" {
  value = module.pybullet_host.private_ip
}
