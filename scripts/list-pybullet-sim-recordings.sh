#!/usr/bin/env bash
# List PyBullet sim GIFs in the OpenTofu sim artifacts bucket (prefix sim-runs/ by default).
# Usage:
#   ./scripts/list-pybullet-sim-recordings.sh              # table: time, size, s3 URI
#   ./scripts/list-pybullet-sim-recordings.sh --uris-only    # one s3:// URI per line, newest first
# Env: AWS_PROFILE (default personal), PYBULLET_S3_PREFIX (default sim-runs)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA="${REPO_ROOT}/infrastructure"
PROFILE="${AWS_PROFILE:-personal}"
PREFIX="${PYBULLET_S3_PREFIX:-sim-runs}"
URIS_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --uris-only) URIS_ONLY=1 ;;
    -h|--help)
      echo "Usage: $0 [--uris-only]"
      exit 0
      ;;
  esac
done

cd "${INFRA}"
command -v tofu >/dev/null 2>&1 || { echo "Install OpenTofu (tofu)" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "Install AWS CLI" >&2; exit 1; }

BUCKET="$(tofu output -raw pybullet_sim_artifacts_bucket)"
REGION="$(tofu output -raw aws_region)"
export AWS_EC2_METADATA_DISABLED=true
export AWS_PAGER=""

export BUCKET
if [[ "${URIS_ONLY}" -eq 1 ]]; then
  aws --profile "${PROFILE}" s3api list-objects-v2 \
    --bucket "${BUCKET}" \
    --prefix "${PREFIX}/" \
    --region "${REGION}" \
    --output json |
    python3 -c "
import json, os, sys
data = json.load(sys.stdin)
items = data.get('Contents') or []
items = [o for o in items if o['Key'].lower().endswith('.gif')]
items.sort(key=lambda o: o['LastModified'], reverse=True)
b = os.environ['BUCKET']
for o in items:
    print(f's3://{b}/{o[\"Key\"]}')
"
  exit 0
fi

echo "Bucket: ${BUCKET}  Region: ${REGION}  Prefix: ${PREFIX}/  Profile: ${PROFILE}"
echo ""

aws --profile "${PROFILE}" s3api list-objects-v2 \
  --bucket "${BUCKET}" \
  --prefix "${PREFIX}/" \
  --region "${REGION}" \
  --output json |
  python3 -c "
import json, os, sys
data = json.load(sys.stdin)
items = data.get('Contents') or []
items = [o for o in items if o['Key'].lower().endswith('.gif')]
items.sort(key=lambda o: o['LastModified'], reverse=True)
b = os.environ['BUCKET']
if not items:
    print('(no .gif objects under this prefix)')
else:
    print(f'{\"LastModified\":<32} {\"Size\":>10}  S3 URI')
    print('-' * 90)
    for o in items:
        lm = str(o['LastModified'])
        sz = o['Size']
        print(f'{lm:<32} {sz:>10}  s3://{b}/{o[\"Key\"]}')
"
