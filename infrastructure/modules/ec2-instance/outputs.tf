output "instance_id" {
  value       = aws_instance.this.id
  description = "Id of the EC2 instance."
}

output "subnet_id" {
  value       = aws_instance.this.subnet_id
  description = "Subnet id the instance is in (compare with a public subnet in the console for SSM over the internet)."
}

output "public_ip" {
  value       = aws_instance.this.public_ip
  description = "Public IP if the subnet maps a public IP; otherwise may be null."
}

output "private_ip" {
  value       = aws_instance.this.private_ip
  description = "Private IP of the instance."
}

output "iam_role_name" {
  value       = aws_iam_role.this.name
  description = "Instance IAM role (SSM enabled)."
}

output "security_group_id" {
  value       = aws_security_group.this.id
  description = "Security group id attached to the instance."
}
