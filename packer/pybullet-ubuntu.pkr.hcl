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
  description = "VPC for the temporary build instance (must reach the internet for apt and DCV tarball)."
}

variable "subnet_id" {
  type        = string
  description = "Subnet id (typically public) for the build instance."
}

variable "project_name" {
  type        = string
  description = "Tag Project and AMI name prefix."
}

variable "aws_cli_profile" {
  type        = string
  default     = "personal"
  description = "AWS CLI profile for SSM publish (shell-local post-processor on the apply host)."
}

variable "builder_instance_type" {
  type        = string
  default     = "g5.xlarge"
  description = "GPU type for the build so NVIDIA drivers match g4dn/g5/g6 class."
}

source "amazon-ebs" "pybullet_ubuntu" {
  region                      = var.region
  instance_type               = var.builder_instance_type
  associate_public_ip_address = true
  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  communicator            = "ssh"
  ssh_username            = "ubuntu"
  ssh_timeout             = "10m"
  temporary_key_pair_type = "ed25519"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 80
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  ami_name        = "${var.project_name}-pybullet-ubuntu2404-{{timestamp}}"
  ami_description = "Golden Ubuntu 24.04: GNOME + DCV + PyBullet venv + NVIDIA (Packer)"

  tags = {
    Project        = var.project_name
    PyBulletPacker = "golden-ubuntu2404"
    Name           = "${var.project_name}-pybullet-golden"
  }

  snapshot_tags = {
    Project        = var.project_name
    PyBulletPacker = "golden-ubuntu2404"
    Name           = "${var.project_name}-pybullet-snapshot"
  }

  run_tags = {
    Name    = "${var.project_name}-packer-builder"
    Project = var.project_name
  }
}

build {
  sources = ["amazon-ebs.pybullet_ubuntu"]

  provisioner "shell" {
    script          = "${path.root}/scripts/provision-ubuntu.sh"
    execute_command = "chmod +x {{ .Path }}; sudo {{ .Path }}"
  }

  provisioner "shell" {
    expect_disconnect = true
    inline            = ["sudo reboot"]
  }

  provisioner "shell" {
    pause_before = "90s"
    inline = [
      "echo '=== Post-reboot sanity checks ==='",
      "uname -r",
      "echo '--- NVIDIA ---'",
      "nvidia-smi --query-gpu=name,driver_version --format=csv,noheader || echo 'WARN: nvidia-smi failed (non-GPU builder?)'",
      "echo '--- DCV ---'",
      "sudo systemctl is-active dcvserver",
      "echo '--- PyBullet ---'",
      "test -d /opt/pybullet-venv",
      "source /opt/pybullet-venv/bin/activate && python3 -c \"import pybullet as p; c=p.connect(p.DIRECT); p.disconnect(); print('PyBullet OK')\"",
      "echo '=== All sanity checks passed ==='",
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/packer-manifest.json"
    strip_path = true
  }

  post-processor "shell-local" {
    environment_vars = [
      "AWS_PROFILE=${var.aws_cli_profile}",
      "PACKER_MANIFEST=${path.root}/packer-manifest.json",
      "AWS_REGION=${var.region}",
      "PACKER_PROJECT=${var.project_name}",
    ]
    script = "${path.root}/scripts/publish-ami-ssm.sh"
  }
}
