packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.3"
    }
  }
}

variable "region" {
  type        = string
  description = "AWS region for the build instance and resulting AMI."
}

variable "vpc_id" {
  type        = string
  description = "VPC for the temporary build instance (must reach the internet for dnf and DCV tarball)."
}

variable "subnet_id" {
  type        = string
  description = "Subnet id (typically public) for the build instance."
}

variable "project_name" {
  type        = string
  description = "Tag Project and AMI name prefix."
}

variable "builder_instance_type" {
  type        = string
  default     = "g5.xlarge"
  description = "GPU type for the build so NVIDIA drivers and kernel-devel match g4dn/g5/g6 class."
}

source "amazon-ebs" "pybullet_al2023" {
  region                      = var.region
  instance_type               = var.builder_instance_type
  associate_public_ip_address = true
  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-kernel-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  communicator            = "ssh"
  ssh_username            = "ec2-user"
  temporary_key_pair_type = "ed25519"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 80
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  ami_name = "${var.project_name}-pybullet-al2023-{{timestamp}}"
  ami_description = "Golden AL2023: GNOME + DCV + PyBullet venv + NVIDIA (Packer)"

  tags = {
    Project        = var.project_name
    PyBulletPacker = "golden-al2023"
    Name           = "${var.project_name}-pybullet-golden"
  }
}

build {
  sources = ["amazon-ebs.pybullet_al2023"]

  provisioner "shell" {
    script = "${path.root}/scripts/provision-al2023.sh"
  }

  provisioner "shell" {
    expect_disconnect = true
    inline              = ["sudo reboot"]
  }

  provisioner "shell" {
    pause_before = "60s"
    inline = [
      "echo 'post-reboot sanity'",
      "uname -r",
      "test -d /opt/pybullet-venv",
    ]
  }
}
