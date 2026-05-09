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
      echo "  --json      Machine-readable JSON (warn field if no public IPv4)."
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

DCV_URL=""
DCV_NOTE=""
if [[ -n "${PUBLIC_IP}" && "${PUBLIC_IP}" != "None" ]]; then
  DCV_URL="https://${PUBLIC_IP}:8443"
else
  PUBLIC_IP=""
  DCV_NOTE=$'No public IPv4 on this instance yet (subnet / associate_public_ip / boot timing).\nDCV URL unknown — use SSM below; retry describe-instances or tofu refresh after a minute.'
  echo "WARN: ${DCV_NOTE}" >&2
fi

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

DCV_URL_LINE="${DCV_URL}"
HOST_LINE="${PUBLIC_IP}"
[[ -z "${DCV_URL}" ]] && DCV_URL_LINE="(none — no public IPv4 yet; use SSM or retry after association)"
[[ -z "${PUBLIC_IP}" ]] && HOST_LINE="n/a"

if [[ "${JSON_OUT}" -eq 1 ]]; then
  python3 -c "
import json
o = {
  'instance_id': '${INSTANCE_ID}',
  'region': '${REGION}',
  'public_ip': '${PUBLIC_IP}',
  'dcv_url': '${DCV_URL}',
  'dcv_port': 8443,
  'username': 'ubuntu',
  'password_note': 'Set on instance: sudo passwd ubuntu (via SSM)',
  'aws_profile': '${PROFILE}',
}
if not o['public_ip']:
  o['warn'] = 'no public IPv4 on instance (subnet / timing); use SSM'
print(json.dumps(o))
"
  exit 0
fi

cat <<EOF

=== PyBullet host is running ===

DCV (web browser):
  URL:      ${DCV_URL_LINE}
  Username: ubuntu
  Password: whatever you set with: sudo passwd ubuntu (over SSM, see below)

DCV (native client):
  Host: ${HOST_LINE}
  Port: 8443
  User: ubuntu

SSM (set password or debug):
  aws ssm start-session \\
    --target ${INSTANCE_ID} \\
    --region ${REGION} \\
    --profile ${PROFILE}

Public IP: ${HOST_LINE}  (from EC2 API — if tofu output differs, run: cd infrastructure && tofu refresh)

EOF
