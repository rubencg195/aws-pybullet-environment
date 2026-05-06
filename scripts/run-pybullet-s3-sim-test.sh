#!/bin/bash
# Run headless PyBullet sim + S3 GIF upload on the PyBullet EC2 host via SSM Run Command.
# Prereqs: instance running, SSM Online, OpenTofu applied with pybullet_sim bucket + IAM policy.
# Usage: ./scripts/run-pybullet-s3-sim-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA="${REPO_ROOT}/infrastructure"
PY_SCRIPT="${SCRIPT_DIR}/pybullet_deep_test/run_sim_and_upload.py"

if [[ ! -f "${PY_SCRIPT}" ]]; then
  echo "Missing ${PY_SCRIPT}" >&2
  exit 1
fi

cd "${INFRA}"
command -v tofu >/dev/null 2>&1 || { echo "Install OpenTofu (tofu)" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "Install AWS CLI" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Install Python 3" >&2; exit 1; }

INSTANCE_ID="$(tofu output -raw pybullet_host_instance_id)"
REGION="$(tofu output -raw aws_region)"
BUCKET="$(tofu output -raw pybullet_sim_artifacts_bucket)"
PROFILE="${AWS_PROFILE:-personal}"

echo "Instance: ${INSTANCE_ID}  Bucket: ${BUCKET}  Region: ${REGION}  Profile: ${PROFILE}"

AWS=(aws --profile "${PROFILE}")
export AWS_EC2_METADATA_DISABLED=true

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
    echo "SSM never came Online (start the instance if it is stopped)." >&2
    exit 1
  fi
done

B64_PY="$(base64 -w0 < "${PY_SCRIPT}" 2>/dev/null || base64 < "${PY_SCRIPT}" | tr -d '\n')"

CLI_INPUT="$(
  INSTANCE_ID="${INSTANCE_ID}" BUCKET="${BUCKET}" REGION="${REGION}" B64_PY="${B64_PY}" python3 -c "
import json, os, shlex
iid = os.environ['INSTANCE_ID']
bucket = os.environ['BUCKET']
region = os.environ['REGION']
b64 = os.environ['B64_PY']
parts = [
    'set -euo pipefail',
    'export PYBULLET_S3_BUCKET=' + shlex.quote(bucket),
    'export EC2_INSTANCE_ID=' + shlex.quote(iid),
    'export AWS_DEFAULT_REGION=' + shlex.quote(region),
    'echo ' + shlex.quote(b64) + ' | base64 -d > /tmp/pybullet_s3_sim_test.py',
    '/opt/pybullet-venv/bin/python /tmp/pybullet_s3_sim_test.py',
    'rm -f /tmp/pybullet_s3_sim_test.py',
]
cmd = '; '.join(parts)
print(json.dumps({
    'InstanceIds': [iid],
    'DocumentName': 'AWS-RunShellScript',
    'Parameters': {'commands': [cmd]},
}))
"
)"

CMD_ID="$("${AWS[@]}" ssm send-command \
  --cli-input-json "${CLI_INPUT}" \
  --region "${REGION}" \
  --output text \
  --query 'Command.CommandId')"

echo "SSM CommandId: ${CMD_ID}"
sleep 4

for _ in $(seq 1 60); do
  STATUS="$("${AWS[@]}" ssm get-command-invocation \
    --command-id "${CMD_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query Status \
    --output text 2>/dev/null || echo "Pending")"
  if [[ "${STATUS}" == "Success" ]] || [[ "${STATUS}" == "Failed" ]] || [[ "${STATUS}" == "Cancelled" ]]; then
    break
  fi
  sleep 3
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

echo "=== PyBullet S3 sim test finished ==="
