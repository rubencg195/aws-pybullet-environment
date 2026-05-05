#!/bin/bash
# Amazon Linux 2023: GNOME + NICE/Amazon DCV + PyBullet venv + NVIDIA (g4dn/g5/g6).
# Baked by Packer; EC2 launches with empty user_data.
# After first login: sudo passwd ec2-user — https://<public-ip>:8443

set -euxo pipefail
exec > >(tee /var/log/packer-provision-pybullet.log) 2>&1

dnf -y update

IMDS_TOKEN="$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token || echo "")"
INSTANCE_TYPE="$(curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/instance-type || echo "")"
if [ -z "${INSTANCE_TYPE}" ]; then
  echo "WARNING: Could not detect instance type via IMDS. NVIDIA driver install may be skipped."
fi
case "${INSTANCE_TYPE}" in
  g4dn*|g5*|g6*)
    dnf -y install kernel-devel kernel-headers gcc make
    dnf -y install nvidia-release
    dnf -y install nvidia-driver-cuda
    ;;
  *)
    echo "Skipping NVIDIA packages (instance type: ${INSTANCE_TYPE:-unknown})."
    ;;
esac

dnf groupinstall -y "Desktop"
install -d /etc/gdm
touch /etc/gdm/custom.conf
if ! grep -qF 'WaylandEnable=false' /etc/gdm/custom.conf; then
  if grep -q '^\[daemon\]' /etc/gdm/custom.conf; then
    sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm/custom.conf
  else
    printf '%s\n' '[daemon]' 'WaylandEnable=false' >> /etc/gdm/custom.conf
  fi
fi
systemctl set-default graphical.target

dnf -y install \
  python3 \
  python3-pip \
  python3-devel \
  gcc \
  gcc-c++ \
  make \
  git \
  mesa-libGL \
  libgomp

rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
# Pinned NICE DCV 2025.0 (Amazon Linux 2023 x86_64). Update URL + SHA256 together when bumping DCV.
# See: https://www.nice-dcv.com/ and AWS "Install the Amazon DCV Server on Linux".
DCV_TGZ_URL="https://d1uj6qtbmh3dt5.cloudfront.net/2025.0/Servers/nice-dcv-2025.0-20103-amzn2023-x86_64.tgz"
DCV_TGZ_FILE="nice-dcv-2025.0-20103-amzn2023-x86_64.tgz"
DCV_TGZ_SHA256="d98eb986f3b547af22a7732ca26cb6541c3842b9ed57218f503c9acc3b29e7e2"
DCV_DIR="/tmp/dcv-rpms"
rm -rf "${DCV_DIR}"
mkdir -p "${DCV_DIR}"
cd "${DCV_DIR}"
curl -fL -o "${DCV_TGZ_FILE}" "${DCV_TGZ_URL}"
echo "${DCV_TGZ_SHA256}  ${DCV_TGZ_FILE}" | sha256sum -c -
tar -xzf "${DCV_TGZ_FILE}"
shopt -s nullglob
_dcv_subdirs=(nice-dcv-*-amzn2023-x86_64)
if [ ${#_dcv_subdirs[@]} -ne 1 ]; then
  echo "ERROR: expected exactly one nice-dcv-*-amzn2023-x86_64 directory" >&2
  exit 1
fi
cd "${_dcv_subdirs[0]}"
dnf install -y \
  ./nice-dcv-server-*.rpm \
  ./nice-dcv-web-viewer-*.rpm \
  ./nice-xdcv-*.rpm \
  ./nice-dcv-gl-*.rpm

usermod -aG video dcv || true
usermod -aG video ec2-user || true

VENV="/opt/pybullet-venv"
python3 -m venv "${VENV}"
# shellcheck source=/dev/null
source "${VENV}/bin/activate"
pip install --upgrade pip
pip install \
  "numpy>=1.22" \
  "scipy" \
  "pybullet" \
  "Pillow" \
  "matplotlib"
chown -R ec2-user:ec2-user "${VENV}"
if ! grep -q 'pybullet-venv' /home/ec2-user/.bashrc 2>/dev/null; then
  echo "source ${VENV}/bin/activate" >> /home/ec2-user/.bashrc
fi

if [ -f /etc/dcv/dcv.conf ]; then
  if ! grep -qF '[session-management/automatic-console-session]' /etc/dcv/dcv.conf; then
    printf '\n[session-management/automatic-console-session]\n' >> /etc/dcv/dcv.conf
  fi
  if ! grep -qF 'owner="ec2-user"' /etc/dcv/dcv.conf; then
    sed -i '/^\[session-management\/automatic-console-session\]/a owner="ec2-user"\nstorage-root="%home%"' /etc/dcv/dcv.conf
  fi
  sed -i 's/^#create-session/create-session/g' /etc/dcv/dcv.conf || true
fi

if systemctl is-active --quiet firewalld 2>/dev/null; then
  firewall-cmd --permanent --add-port=8443/tcp
  firewall-cmd --reload
fi

systemctl enable dcvserver
systemctl enable gdm
systemctl start gdm || true
systemctl start dcvserver
systemctl restart dcvserver || true

rm -rf "${DCV_DIR}"

echo "=== Provision summary ==="
echo "Kernel: $(uname -r)"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "NVIDIA: not detected (expected on non-GPU builders)"
systemctl is-active dcvserver && echo "DCV: running" || echo "DCV: NOT running"
source "${VENV}/bin/activate" && python -c "import pybullet; print('PyBullet:', pybullet.__version__)" 2>/dev/null || echo "PyBullet: import failed"
echo "=== Provision complete ==="
