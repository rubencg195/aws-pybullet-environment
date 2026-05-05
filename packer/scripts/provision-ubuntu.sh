#!/bin/bash
# Ubuntu 24.04: GNOME + Amazon DCV + PyBullet venv + NVIDIA (g4dn/g5/g6).
# Baked by Packer; EC2 launches with empty user_data.
# After first login: sudo passwd ubuntu — https://<public-ip>:8443

set -euxo pipefail
exec > >(tee /var/log/packer-provision-pybullet.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y upgrade

# --- NVIDIA drivers (GPU instances only) ---
IMDS_TOKEN="$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token || echo "")"
INSTANCE_TYPE="$(curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/instance-type || echo "")"
if [ -z "${INSTANCE_TYPE}" ]; then
  echo "WARNING: Could not detect instance type via IMDS. NVIDIA driver install may be skipped."
fi
case "${INSTANCE_TYPE}" in
  g4dn*|g5*|g6*)
    apt-get -y install linux-headers-$(uname -r) build-essential dkms
    apt-get -y install ubuntu-drivers-common
    ubuntu-drivers install --gpgpu
    ;;
  *)
    echo "Skipping NVIDIA packages (instance type: ${INSTANCE_TYPE:-unknown})."
    ;;
esac

# --- Desktop environment ---
apt-get -y install ubuntu-desktop-minimal
install -d /etc/gdm3
touch /etc/gdm3/custom.conf
if ! grep -qF 'WaylandEnable=false' /etc/gdm3/custom.conf; then
  if grep -q '^\[daemon\]' /etc/gdm3/custom.conf; then
    sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
  else
    printf '%s\n' '[daemon]' 'WaylandEnable=false' >> /etc/gdm3/custom.conf
  fi
fi
systemctl set-default graphical.target

# --- Build tools and Python ---
apt-get -y install \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  gcc \
  g++ \
  make \
  git \
  libgl1-mesa-glx \
  libgomp1 \
  curl \
  wget \
  unzip

# --- Amazon DCV 2025.0 ---
wget -qO /tmp/NICE-GPG-KEY https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
gpg --import /tmp/NICE-GPG-KEY
DCV_TGZ_URL="https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-ubuntu2404-x86_64.tgz"
DCV_TGZ_FILE="nice-dcv-ubuntu2404-x86_64.tgz"
DCV_TGZ_SHA256="a39374d39f2d849bd13ee101970bb9eea15a8c5ec743799b7cbb7f562ece9e17"
DCV_DIR="/tmp/dcv-debs"
rm -rf "${DCV_DIR}"
mkdir -p "${DCV_DIR}"
cd "${DCV_DIR}"
curl -fL -o "${DCV_TGZ_FILE}" "${DCV_TGZ_URL}"
echo "${DCV_TGZ_SHA256}  ${DCV_TGZ_FILE}" | sha256sum -c -
tar -xzf "${DCV_TGZ_FILE}"
shopt -s nullglob
_dcv_subdirs=(nice-dcv-*-ubuntu2404-x86_64)
if [ ${#_dcv_subdirs[@]} -ne 1 ]; then
  echo "ERROR: expected exactly one nice-dcv-*-ubuntu2404-x86_64 directory" >&2
  exit 1
fi
cd "${_dcv_subdirs[0]}"
apt-get -y install \
  ./nice-dcv-server_*.deb \
  ./nice-dcv-web-viewer_*.deb \
  ./nice-xdcv_*.deb \
  ./nice-dcv-gl_*.deb

usermod -aG video dcv || true
usermod -aG video ubuntu || true

# --- PyBullet virtual environment ---
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
chown -R ubuntu:ubuntu "${VENV}"
if ! grep -q 'pybullet-venv' /home/ubuntu/.bashrc 2>/dev/null; then
  echo "source ${VENV}/bin/activate" >> /home/ubuntu/.bashrc
fi

# --- DCV config: automatic console session ---
if [ -f /etc/dcv/dcv.conf ]; then
  if ! grep -qF '[session-management/automatic-console-session]' /etc/dcv/dcv.conf; then
    printf '\n[session-management/automatic-console-session]\n' >> /etc/dcv/dcv.conf
  fi
  if ! grep -qF 'owner="ubuntu"' /etc/dcv/dcv.conf; then
    sed -i '/^\[session-management\/automatic-console-session\]/a owner="ubuntu"\nstorage-root="%home%"' /etc/dcv/dcv.conf
  fi
  sed -i 's/^#create-session/create-session/g' /etc/dcv/dcv.conf || true
fi

# --- Firewall ---
if command -v ufw &>/dev/null && ufw status | grep -q active; then
  ufw allow 8443/tcp
fi

# --- Enable services ---
systemctl enable dcvserver
systemctl enable gdm
systemctl start gdm || true
systemctl start dcvserver
systemctl restart dcvserver || true

# --- Cleanup ---
rm -rf "${DCV_DIR}"
rm -f /tmp/NICE-GPG-KEY
apt-get -y autoremove
apt-get -y clean

echo "=== Provision summary ==="
echo "OS: $(lsb_release -ds)"
echo "Kernel: $(uname -r)"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "NVIDIA: not detected (expected on non-GPU builders)"
systemctl is-active dcvserver && echo "DCV: running" || echo "DCV: NOT running"
source "${VENV}/bin/activate" && python3 -c "import pybullet; print('PyBullet:', pybullet.__version__)" 2>/dev/null || echo "PyBullet: import failed"
echo "=== Provision complete ==="
