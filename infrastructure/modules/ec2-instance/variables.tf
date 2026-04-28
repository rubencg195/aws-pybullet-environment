variable "project_name" {
  type        = string
  description = "Prefix for resource names and common tags."
}

variable "vpc_id" {
  type        = string
  description = "VPC id for the instance, security group, and subnet discovery."
}

variable "instance_type" {
  type        = string
  default     = "g4dn.2xlarge"
  description = "EC2 instance type (default is g4dn.2xlarge for GPU workloads)."
}

variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name for SSH access."
}

variable "subnet_id" {
  type        = string
  default     = null
  description = "Subnet for the instance. If null, the first default-VPC subnet is used."
}

variable "sg_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks for SSH (22) and NICE DCV (8443)."
}
variable "root_volume_size_gb" {
  type        = number
  default     = 80
  description = "Root EBS volume size in GiB (PyBullet, wheels, and CUDA tooling need space if added later)."
}

variable "user_data" {
  type        = string
  default     = null
  description = "Override bootstrap script. If null, the built-in user_data.sh is used."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags to merge onto the instance and security group."
}
