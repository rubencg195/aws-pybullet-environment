#!/usr/bin/env bash
#
# SSM session to the PyBullet EC2 host (WSL / Linux / macOS).
# After connect:  sudo passwd ec2-user
#
# Requires: AWS CLI v2, Session Manager plugin, SSM "Online" on the instance.
# Optional:  export AWS_PROFILE   export AWS_REGION
#
# Run from repository root (recommended):
#   chmod +x src/ssm-ec2-inital-setup/ssm-connect.sh
#   ./src/ssm-ec2-inital-setup/ssm-connect.sh
#

set -euo pipefail
set +H

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../src/ssm-ec2-inital-setup  ->  repo root is two levels up
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IAC_DIR="${ROOT_DIR}/infrastructure"
cd "${IAC_DIR}" || {
  echo "error: expected ${IAC_DIR}" >&2
  exit 1
}

: "${AWS_PROFILE:=personal}"
: "${AWS_REGION:=}"

IAC="terraform"
if ! command -v terraform >/dev/null 2>&1; then
  IAC="tofu"
fi
if ! command -v "${IAC}" >/dev/null 2>&1; then
  echo "error: install HashiCorp Terraform (terraform) or OpenTofu (tofu); apply the stack in ${IAC_DIR} first" >&2
  exit 1
fi

if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(${IAC} output -raw aws_region 2>/dev/null || true)"
fi
if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(aws configure get region --profile "${AWS_PROFILE}" 2>/dev/null || true)"
fi
if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="us-east-1"
fi

INSTANCE_ID="$(${IAC} output -raw pybullet_host_instance_id)"

exec aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}"
