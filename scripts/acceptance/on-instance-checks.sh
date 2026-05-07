#!/bin/bash
# Run on the PyBullet EC2 instance (ubuntu user or root via SSM). Exit non-zero on failure.
set -euo pipefail

FAILS=0
WARNS=0
warn() { echo "WARN: $*" >&2; WARNS=$((WARNS + 1)); }
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }

echo "=== Acceptance checks (on instance) ==="

if grep -q '^VERSION_ID="24.04' /etc/os-release 2>/dev/null || grep -q '^VERSION_ID=24.04' /etc/os-release 2>/dev/null; then
  echo "OK: Ubuntu 24.04"
else
  fail "Expected Ubuntu 24.04 (check /etc/os-release)"
fi

if systemctl is-active --quiet dcvserver 2>/dev/null; then
  echo "OK: dcvserver active"
else
  fail "dcvserver is not active"
fi

if command -v ss >/dev/null 2>&1 && ss -lnpt 2>/dev/null | grep -q ':8443'; then
  echo "OK: something listening on TCP 8443"
else
  warn "Could not confirm :8443 listener (ss missing or no match); continuing"
fi

if [[ -x /usr/bin/code ]] || dpkg -l code 2>/dev/null | grep -q '^ii'; then
  echo "OK: Visual Studio Code package present"
else
  fail "VS Code (code) not installed"
fi

if [[ -d /opt/pybullet-venv ]]; then
  if /opt/pybullet-venv/bin/python3 -c "import pybullet as p; c=p.connect(p.DIRECT); p.disconnect()" 2>/dev/null; then
    echo "OK: PyBullet import (DIRECT)"
  else
    fail "PyBullet import failed in /opt/pybullet-venv"
  fi
else
  fail "/opt/pybullet-venv missing"
fi

IMDS_TOKEN="$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token || true)"
INSTANCE_TYPE="$(curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/instance-type || echo "")"
case "${INSTANCE_TYPE}" in
  g4dn*|g5*|g6*)
    if nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null 2>&1; then
      echo "OK: nvidia-smi (${INSTANCE_TYPE})"
    else
      msg="GPU instance ${INSTANCE_TYPE} but nvidia-smi failed (DKMS/kernel drift — rebuild AMI or replace instance; see TROUBLESHOOTING.md)"
      if [[ "${STRICT_ACCEPTANCE_GPU:-0}" == "1" ]]; then
        fail "${msg}"
      else
        warn "${msg}"
      fi
    fi
    ;;
  *)
    echo "SKIP: NVIDIA check (instance type: ${INSTANCE_TYPE:-unknown})"
    ;;
esac

if [[ "${FAILS}" -eq 0 ]]; then
  echo "=== All required on-instance checks passed ==="
  if [[ "${WARNS}" -gt 0 ]]; then
    echo "=== ${WARNS} warning(s) (non-fatal) ===" >&2
  fi
  exit 0
fi

echo "=== ${FAILS} check(s) failed ===" >&2
exit 1
