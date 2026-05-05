# -----------------------------------------------------------------------------
# Packer golden AMI (Ubuntu 24.04 + GNOME + DCV + PyBullet + NVIDIA on g5-class).
# null_resource runs `packer build`; post-processors write the AMI id to SSM.
# EC2 reads SSM Parameter: local.packer_golden_ami_ssm_parameter_name
# First-time: if `tofu plan` errors on missing parameter, run:
#   tofu apply -auto-approve -target=null_resource.packer_pybullet_ami[0]
# Or set local.packer_ami_id_override to an existing AMI id (skip Packer in OpenTofu).
# IAM: apply principal needs ssm:PutParameter + ssm:GetParameter on that parameter (and Packer EC2 perms).
# -----------------------------------------------------------------------------

resource "null_resource" "packer_pybullet_ami" {
  count = local.packer_ami_id_override == null ? 1 : 0

  triggers = {
    pkr_hcl     = filesha256("${path.module}/../packer/pybullet-ubuntu.pkr.hcl")
    provisioner = filesha256("${path.module}/../packer/scripts/provision-ubuntu.sh")
    publish_ssm = filesha256("${path.module}/../packer/scripts/publish-ami-ssm.sh")
    ssm_param   = local.packer_golden_ami_ssm_parameter_name
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
      packer init pybullet-ubuntu.pkr.hcl
      packer validate \
        -var "region=${data.aws_region.current.id}" \
        -var "vpc_id=${data.aws_vpc.this.id}" \
        -var "subnet_id=${local.packer_subnet_id}" \
        -var "project_name=${local.project_name}" \
        -var "aws_cli_profile=${local.aws_cli_profile}" \
        pybullet-ubuntu.pkr.hcl
      packer build \
        -var "region=${data.aws_region.current.id}" \
        -var "vpc_id=${data.aws_vpc.this.id}" \
        -var "subnet_id=${local.packer_subnet_id}" \
        -var "project_name=${local.project_name}" \
        -var "aws_cli_profile=${local.aws_cli_profile}" \
        pybullet-ubuntu.pkr.hcl
    EOF
  }
}

data "aws_ssm_parameter" "golden_ami_id" {
  count = local.packer_ami_id_override == null ? 1 : 0

  depends_on = [null_resource.packer_pybullet_ami[0]]

  name = local.packer_golden_ami_ssm_parameter_name
}
