#!/bin/bash
# Amazon Linux 2023: GNOME (Desktop) + NICE/Amazon DCV for remote GUI, and PyBullet in a venv.
# Ref: https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html
# After boot: set password for DCV login —  sudo passwd ec2-user
# Open in browser: https://<public-ip>:8443

set -euxo pipefail
exec > >(tee /var/log/user-data-pyb.log) 2>&1

dnf -y update

# --- Graphical environment (required for DCV console sessions on AL2023) -----------------------
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

# --- Build / scientific stack deps for PyBullet ------------------------------------------------
# Do not install the full `curl` RPM: AL2023 keeps `curl-minimal` for /usr/bin/curl (Desktop pulls it).
# Explicit `dnf install curl` fails with conflicting packages vs curl-minimal and breaks cloud-init.
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

# --- NICE/Amazon DCV (GPG + tarball from official CloudFront; version tracks “latest” symlink) ----
rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
DCV_TGZ="nice-dcv-amzn2023-x86_64.tgz"
DCV_DIR="/tmp/dcv-rpms"
rm -rf "${DCV_DIR}"
mkdir -p "${DCV_DIR}"
cd "${DCV_DIR}"
curl -fL -O "https://d1uj6qtbmh3dt5.cloudfront.net/${DCV_TGZ}"
tar -xzf "${DCV_TGZ}"
shopt -s nullglob
_dcv_subdirs=(nice-dcv-*-amzn2023-x86_64)
if [ ${#_dcv_subdirs[@]} -ne 1 ]; then
  echo "ERROR: expected exactly one nice-dcv-*-amzn2023-x86_64 directory" >&2
  exit 1
fi
cd "${_dcv_subdirs[0]}"
# Install from local RPMs; dnf still pulls Amazon Linux dependencies from enabled repos.
dnf install -y \
  ./nice-dcv-server-*.rpm \
  ./nice-dcv-web-viewer-*.rpm \
  ./nice-xdcv-*.rpm \
  ./nice-dcv-gl-*.rpm

usermod -aG video dcv || true

# --- PyBullet venv (PEP 668 / externally-managed) -----------------------------------------------
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

# --- DCV: prefer automatic console for ec2-user (see AWS re:Post AL2023 + DCV) --------------------
if [ -f /etc/dcv/dcv.conf ] && grep -qF '[session-management/automatic-console-session]' /etc/dcv/dcv.conf; then
  if ! grep -qF 'owner="ec2-user"' /etc/dcv/dcv.conf; then
    sed -i '/^\[session-management\/automatic-console-session\]/a owner="ec2-user"\nstorage-root="%home%"' /etc/dcv/dcv.conf
  fi
  sed -i 's/^#create-session/create-session/g' /etc/dcv/dcv.conf || true
fi

# --- Local firewall (if enabled) ----------------------------------------------------------------
if systemctl is-active --quiet firewalld 2>/dev/null; then
  firewall-cmd --permanent --add-port=8443/tcp
  firewall-cmd --reload
fi

systemctl enable dcvserver
systemctl enable gdm
systemctl start gdm || true
systemctl start dcvserver
systemctl restart dcvserver || true

{
  echo "NICE/Amazon DCV is on port 8443 (SG must allow 8443 from your client)."
  echo "1) sudo passwd ec2-user"
  echo "2) https://<this-host-public-ip>:8443"
} | tee /var/log/dcv-README.txt

# Graphical + DCV often need one reboot after first install.
reboot
