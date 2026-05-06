#!/usr/bin/env bash
# Download a PyBullet sim recording from S3 (or HTTPS S3 virtual-hosted URL).
# Usage:
#   ./scripts/download-pybullet-sim-recording.sh s3://bucket/key [out_path]
#   ./scripts/download-pybullet-sim-recording.sh https://bucket.s3.us-east-1.amazonaws.com/key [out_path]
#   ./scripts/download-pybullet-sim-recording.sh sim-runs/i-xxx/.../file.gif [out_path]  # uses tofu bucket
# Env: AWS_PROFILE (default personal)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA="${REPO_ROOT}/infrastructure"
PROFILE="${AWS_PROFILE:-personal}"

if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  echo "Usage: $0 <s3_uri|https_s3_url|key_under_bucket> [destination_file]"
  echo "  destination_file defaults to ./<basename> in the current working directory."
  exit 1
fi

RAW="$1"
OUT="${2:-}"

cd "${INFRA}"
command -v tofu >/dev/null 2>&1 || { echo "Install OpenTofu (tofu)" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "Install AWS CLI" >&2; exit 1; }

BUCKET="$(tofu output -raw pybullet_sim_artifacts_bucket)"
REGION="$(tofu output -raw aws_region)"
export AWS_EC2_METADATA_DISABLED=true

S3_URI="$(
  python3 -c "
import os, re, sys
raw = sys.argv[1]
bucket = sys.argv[2]
if raw.startswith('s3://'):
    print(raw)
    sys.exit(0)
# Virtual-hosted–style URLs
m = re.match(r'^https?://([0-9a-z.-]+)\.s3\.([a-z0-9-]+)\.amazonaws\.com/(.+)$', raw, re.I)
if m:
    b, _, key = m.group(1), m.group(2), m.group(3)
    print(f's3://{b}/{key}')
    sys.exit(0)
m = re.match(r'^https?://([0-9a-z.-]+)\.s3\.amazonaws\.com/(.+)$', raw, re.I)
if m:
    print(f's3://{m.group(1)}/{m.group(2)}')
    sys.exit(0)
# Treat as key in default bucket
if '/' in raw and not raw.startswith('http'):
    print(f's3://{bucket}/{raw.lstrip(\"/\")}')
    sys.exit(0)
print('Could not parse URL or key', file=sys.stderr)
sys.exit(1)
" "${RAW}" "${BUCKET}"
)"

if [[ -z "${OUT}" ]]; then
  if [[ "${S3_URI}" =~ ^s3://[^/]+/(.+)$ ]]; then
    OUT="$(basename "${BASH_REMATCH[1]}")"
  else
    OUT="recording.gif"
  fi
fi

cd "${REPO_ROOT}"
echo "Source: ${S3_URI}"
echo "Dest:   ${REPO_ROOT}/${OUT}  (region ${REGION}, profile ${PROFILE})"

aws --profile "${PROFILE}" s3 cp "${S3_URI}" "${OUT}" --region "${REGION}"
echo "OK: wrote ${OUT}"
