#!/bin/bash
# Run from your workstation with AWS CLI + OpenTofu configured (same profile as infrastructure/provider.tf).
# Usage: ./scripts/run-acceptance.sh [--skip-external]
set -euo pipefail

SKIP_EXTERNAL=0
for arg in "$@"; do
  case "$arg" in
    --skip-external) SKIP_EXTERNAL=1 ;;
    -h|--help)
      echo "Usage: $0 [--skip-external]"
      echo "  --skip-external  Do not curl the public DCV URL (useful if IP/SG blocks this machine)."
      echo ""
      echo "Environment:"
      echo "  STRICT_ACCEPTANCE_GPU=1  Fail the run if nvidia-smi does not work on g4/g5/g6 (default: warn only)."
      exit 0
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA="${REPO_ROOT}/infrastructure"
REMOTE_SCRIPT="${SCRIPT_DIR}/acceptance/on-instance-checks.sh"

if [[ ! -f "${REMOTE_SCRIPT}" ]]; then
  echo "Missing ${REMOTE_SCRIPT}" >&2
  exit 1
fi

cd "${INFRA}"
command -v tofu >/dev/null 2>&1 || { echo "Install OpenTofu (tofu)" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "Install AWS CLI" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Install Python 3 (for SSM JSON payload)" >&2; exit 1; }

INSTANCE_ID="$(tofu output -raw pybullet_host_instance_id)"
REGION="$(tofu output -raw aws_region)"
DCV_URL="$(tofu output -raw pybullet_host_dcv_url)"
# Match infrastructure/local.tf default when AWS_PROFILE is unset (avoids hanging on credential discovery).
PROFILE="${AWS_PROFILE:-personal}"

echo "Instance: ${INSTANCE_ID}  Region: ${REGION}  AWS profile: ${PROFILE}"

AWS=(aws --profile "${PROFILE}")
export AWS_EC2_METADATA_DISABLED=true

# shellcheck source=lib/ec2-host-precheck.sh
source "${SCRIPT_DIR}/lib/ec2-host-precheck.sh"
ec2_host_precheck || exit 1

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
    echo "SSM never came Online; fix IAM / instance role / agent, then retry." >&2
    exit 1
  fi
done

STRICT_GPU="${STRICT_ACCEPTANCE_GPU:-0}"
[[ "${STRICT_GPU}" == "1" ]] || STRICT_GPU=0

CLI_INPUT="$(
  REMOTE_SCRIPT_PATH="${REMOTE_SCRIPT}" INSTANCE_ID="${INSTANCE_ID}" STRICT_ACCEPTANCE_GPU="${STRICT_GPU}" python3 -c "
import base64, json, os, pathlib
p = pathlib.Path(os.environ['REMOTE_SCRIPT_PATH'])
b64 = base64.b64encode(p.read_bytes()).decode('ascii')
strict = os.environ.get('STRICT_ACCEPTANCE_GPU', '0')
prefix = f'export STRICT_ACCEPTANCE_GPU={strict}; '
print(json.dumps({
  'InstanceIds': [os.environ['INSTANCE_ID']],
  'DocumentName': 'AWS-RunShellScript',
  'Parameters': {'commands': [prefix + f'echo {b64} | base64 -d | bash']},
}))
"
)"

CMD_ID="$("${AWS[@]}" ssm send-command \
  --cli-input-json "${CLI_INPUT}" \
  --region "${REGION}" \
  --output text \
  --query 'Command.CommandId')"

echo "SSM CommandId: ${CMD_ID}"
sleep 3

for i in $(seq 1 30); do
  STATUS="$("${AWS[@]}" ssm get-command-invocation \
    --command-id "${CMD_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query Status \
    --output text 2>/dev/null || echo "Pending")"
  if [[ "${STATUS}" == "Success" ]] || [[ "${STATUS}" == "Failed" ]] || [[ "${STATUS}" == "Cancelled" ]]; then
    break
  fi
  sleep 2
done

OUT="$("${AWS[@]}" ssm get-command-invocation \
  --command-id "${CMD_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" \
  --output text \
  --query StandardOutputContent 2>/dev/null || true)"
ERR="$("${AWS[@]}" ssm get-command-invocation \
  --command-id "${CMD_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" \
  --output text \
  --query StandardErrorContent 2>/dev/null || true)"

echo "--- Remote stdout ---"
echo "${OUT}"
if [[ -n "${ERR}" ]]; then
  echo "--- Remote stderr ---"
  echo "${ERR}"
fi

FINAL="$("${AWS[@]}" ssm get-command-invocation \
  --command-id "${CMD_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" \
  --query Status \
  --output text)"

if [[ "${FINAL}" != "Success" ]]; then
  echo "SSM command status: ${FINAL}" >&2
  exit 1
fi

if [[ "${SKIP_EXTERNAL}" -eq 1 ]]; then
  echo "Skipping external DCV curl (--skip-external)."
  exit 0
fi

echo "=== External smoke: DCV TLS endpoint (${DCV_URL}) ==="
HTTP_CODE="$(curl -fsS -k --max-time 15 -o /dev/null -w '%{http_code}' "${DCV_URL}/" || echo "000")"
if [[ "${HTTP_CODE}" =~ ^(200|302|301|401|403)$ ]]; then
  echo "OK: HTTP ${HTTP_CODE} from DCV URL (reachable from this host)"
else
  echo "WARN: HTTP ${HTTP_CODE} from DCV URL — check SG / public IP / VPN (DCV may still work from your network)" >&2
fi

echo "=== Acceptance run finished ==="
