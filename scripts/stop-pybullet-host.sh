#!/usr/bin/env bash
# Stop the PyBullet EC2 host (saves compute; EBS root volume still billed).
# Uses OpenTofu outputs for instance id and region (same as other workstation scripts).
#
# Usage: ./scripts/stop-pybullet-host.sh [--wait]
#   --wait   Block until the instance reaches stopped (via aws ec2 wait instance-stopped).
#
# Env: AWS_PROFILE (default: personal)
#
# Note: A later `tofu apply` may start the instance again if desired state is running.
set -euo pipefail

WAIT=0
for arg in "$@"; do
  case "$arg" in
    --wait) WAIT=1 ;;
    -h|--help)
      echo "Usage: $0 [--wait]"
      echo "  Stop the PyBullet host from tofu outputs (pybullet_host_instance_id, aws_region)."
      echo "  --wait  Wait until instance-stopped."
      exit 0
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA="${REPO_ROOT}/infrastructure"
PROFILE="${AWS_PROFILE:-personal}"

cd "${INFRA}"
command -v tofu >/dev/null 2>&1 || { echo "Install OpenTofu (tofu) or add it to PATH." >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "Install AWS CLI." >&2; exit 1; }

INSTANCE_ID="$(tofu output -raw pybullet_host_instance_id)"
REGION="$(tofu output -raw aws_region)"
export AWS_EC2_METADATA_DISABLED=true
AWS=(aws --profile "${PROFILE}")

line="$("${AWS[@]}" ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --region "${REGION}" \
  --query 'Reservations[0].Instances[0].[State.Name,Tags[?Key==`Name`].Value | [0]]' \
  --output text 2>/dev/null || true)"

if [[ -z "${line}" || "${line}" == "None" ]]; then
  echo "Cannot describe instance ${INSTANCE_ID} in ${REGION} (check profile ${PROFILE})." >&2
  exit 1
fi

state=""
name=""
IFS=$'\t' read -r state name <<< "${line}" || true
[[ "${name}" == "None" ]] && name=""

if [[ "${name}" == *packer-builder* ]]; then
  echo "Refusing to stop Packer builder instance (${INSTANCE_ID}). Use the PyBullet host id." >&2
  exit 1
fi

case "${state}" in
  terminated)
    echo "Instance ${INSTANCE_ID} is terminated; nothing to stop." >&2
    exit 1
    ;;
  stopping|stopped)
    echo "Instance ${INSTANCE_ID} is already ${state}."
    if [[ "${WAIT}" -eq 1 && "${state}" == "stopping" ]]; then
      "${AWS[@]}" ec2 wait instance-stopped --instance-ids "${INSTANCE_ID}" --region "${REGION}"
      echo "Instance is stopped."
    fi
    exit 0
    ;;
esac

echo "Stopping ${INSTANCE_ID} (${name:-unknown name}) in ${REGION} (profile ${PROFILE})..."
"${AWS[@]}" ec2 stop-instances --instance-ids "${INSTANCE_ID}" --region "${REGION}" --output text

if [[ "${WAIT}" -eq 1 ]]; then
  echo "Waiting for instance-stopped..."
  "${AWS[@]}" ec2 wait instance-stopped --instance-ids "${INSTANCE_ID}" --region "${REGION}"
  echo "Instance is stopped."
else
  echo "Stop requested. Use --wait to block until stopped."
fi
