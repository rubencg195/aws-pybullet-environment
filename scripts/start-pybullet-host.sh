#!/usr/bin/env bash
# Start the PyBullet EC2 host if stopped, wait until running, then print DCV / SSM login hints.
# Uses OpenTofu outputs for instance id and region; public IP is read from the live EC2 API
# (tofu output can be stale until refresh, especially after stop/start).
#
# Usage: ./scripts/start-pybullet-host.sh [--wait-ssm] [--json]
#   --wait-ssm   After running, poll until SSM reports Online (default ~3 min max).
#   --json       Print one JSON object with login fields (no decorative text).
#
# Env: AWS_PROFILE (default: personal), EC2_START_WAIT_MAX_SEC (default: 600)
set -euo pipefail

WAIT_SSM=0
JSON_OUT=0
for arg in "$@"; do
  case "$arg" in
    --wait-ssm) WAIT_SSM=1 ;;
    --json) JSON_OUT=1 ;;
    -h|--help)
      echo "Usage: $0 [--wait-ssm] [--json]"
      echo "  Start stopped PyBullet host (from tofu outputs), wait running, print login info."
      echo "  --wait-ssm  Wait until SSM agent is Online (useful before run-acceptance / sim scripts)."
      echo "  --json      Machine-readable output (dcv_url, public_ip, instance_id, region, ...)."
      echo ""
      echo "Env: AWS_PROFILE (default personal), EC2_START_WAIT_MAX_SEC (default 600)"
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

# shellcheck source=lib/ec2-host-precheck.sh
source "${SCRIPT_DIR}/lib/ec2-host-precheck.sh"
ec2_host_precheck || exit 1

PUBLIC_IP="$("${AWS[@]}" ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --region "${REGION}" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text 2>/dev/null || true)"

if [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" == "None" ]]; then
  echo "EC2: no PublicIpAddress yet for ${INSTANCE_ID} (subnet / associate_public_ip?)." >&2
  exit 1
fi

DCV_URL="https://${PUBLIC_IP}:8443"

if [[ "${WAIT_SSM}" -eq 1 ]]; then
  echo "Waiting for SSM agent (up to ~3 min)..."
  for i in $(seq 1 36); do
    PING="$("${AWS[@]}" ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
      --region "${REGION}" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null || echo "")"
    if [[ "${PING}" == "Online" ]]; then
      echo "SSM: Online"
      break
    fi
    sleep 5
    if [[ "${i}" -eq 36 ]]; then
      echo "WARN: SSM not Online yet — DCV may still work; check IAM / agent later." >&2
    fi
  done
fi

if [[ "${JSON_OUT}" -eq 1 ]]; then
  python3 -c "
import json
print(json.dumps({
  'instance_id': '${INSTANCE_ID}',
  'region': '${REGION}',
  'public_ip': '${PUBLIC_IP}',
  'dcv_url': '${DCV_URL}',
  'dcv_port': 8443,
  'username': 'ubuntu',
  'password_note': 'Set on instance: sudo passwd ubuntu (via SSM)',
  'aws_profile': '${PROFILE}',
}))
"
  exit 0
fi

cat <<EOF

=== PyBullet host is running ===

DCV (web browser):
  URL:      ${DCV_URL}
  Username: ubuntu
  Password: whatever you set with: sudo passwd ubuntu (over SSM, see below)

DCV (native client):
  Host: ${PUBLIC_IP}
  Port: 8443
  User: ubuntu

SSM (set password or debug):
  aws ssm start-session \\
    --target ${INSTANCE_ID} \\
    --region ${REGION} \\
    --profile ${PROFILE}

Public IP: ${PUBLIC_IP}  (from EC2 API — if tofu output differs, run: cd infrastructure && tofu refresh)

EOF
