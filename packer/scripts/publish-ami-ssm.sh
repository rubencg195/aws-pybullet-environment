#!/bin/bash
# Called by Packer shell-local post-processor after manifest is written.
# Publishes the new AMI id to SSM Parameter Store for OpenTofu to read.
set -euo pipefail
MAN="${PACKER_MANIFEST:?PACKER_MANIFEST not set}"
REGION="${AWS_REGION:?AWS_REGION not set}"
PROJECT="${PACKER_PROJECT:?PACKER_PROJECT not set}"
if [[ ! -f "$MAN" ]]; then
  echo "ERROR: manifest not found: $MAN" >&2
  exit 1
fi
AMI_ID="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['builds'][-1]['artifact_id'].split(':')[-1])" "$MAN")"
NAME="/pybullet/${PROJECT}/golden-ami-id"
aws ssm put-parameter --name "$NAME" --value "$AMI_ID" --type String --overwrite --region "$REGION" >/dev/null
rm -f "$MAN"
echo "Published golden AMI ${AMI_ID} to SSM ${NAME}"
