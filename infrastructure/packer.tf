# -----------------------------------------------------------------------------
# Packer golden AMI (AL2023 + GNOME + DCV + PyBullet + NVIDIA on g5-class).
# null_resource runs `packer build`; EC2 uses data.aws_ami filter on self-owned tags.
# First-time: if `tofu plan` errors on missing AMI, run:
#   tofu apply -auto-approve -target=null_resource.packer_pybullet_ami
# Or set local.packer_ami_id_override to an existing AMI id (skip Packer in OpenTofu).
# -----------------------------------------------------------------------------

resource "null_resource" "packer_pybullet_ami" {
  count = local.packer_ami_id_override == null ? 1 : 0

  triggers = {
    pkr_hcl     = filesha256("${path.module}/../packer/pybullet-al2023.pkr.hcl")
    provisioner = filesha256("${path.module}/../packer/scripts/provision-al2023.sh")
  }

  lifecycle {
    precondition {
      condition     = local.packer_subnet_id != null
      error_message = "Packer needs a subnet with internet access: set local.ec2_subnet_id or add a subnet in vpc_name whose Name tag matches *public*."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      set -euo pipefail
      export AWS_PROFILE="${local.aws_cli_profile}"
      export PACKER_LOG=0
      ROOT="${abspath("${path.module}/../packer")}"
      cd "$ROOT"
      command -v packer >/dev/null 2>&1 || { echo "Install Packer: https://developer.hashicorp.com/packer/install"; exit 1; }
      packer init .
      packer validate pybullet-al2023.pkr.hcl
      packer build \
        -var "region=${data.aws_region.current.id}" \
        -var "vpc_id=${data.aws_vpc.this.id}" \
        -var "subnet_id=${local.packer_subnet_id}" \
        -var "project_name=${local.project_name}" \
        pybullet-al2023.pkr.hcl
    EOF
  }
}

data "aws_ami" "pybullet_golden" {
  count = local.packer_ami_id_override == null ? 1 : 0

  depends_on = [null_resource.packer_pybullet_ami[0]]

  most_recent = true
  owners      = [data.aws_caller_identity.current.account_id]

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "tag:Project"
    values = [local.project_name]
  }
  filter {
    name   = "tag:PyBulletPacker"
    values = ["golden-al2023"]
  }
}
