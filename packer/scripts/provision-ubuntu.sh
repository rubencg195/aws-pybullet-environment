#!/bin/bash
# Ubuntu 24.04: GNOME + VS Code + Amazon DCV + PyBullet venv + NVIDIA (g4dn/g5/g6).
# Baked by Packer; EC2 launches with empty user_data.
# After first login: sudo passwd ubuntu — https://<public-ip>:8443

set -euxo pipefail
exec > >(tee /var/log/packer-provision-pybullet.log) 2>&1

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

mkdir -p /etc/needrestart/conf.d
echo '$nrconf{restart} = "a";' > /etc/needrestart/conf.d/99-autorestart.conf

apt-get update
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

# Detect GPU instance type via IMDSv2
IMDS_TOKEN="$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token || echo "")"
INSTANCE_TYPE="$(curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/instance-type || echo "")"
if [ -z "${INSTANCE_TYPE}" ]; then
  echo "WARNING: Could not detect instance type via IMDS. NVIDIA driver install may be skipped."
fi

# Install headers for the NEWEST kernel (the one that will run after reboot),
# not just the currently running one. apt-get upgrade may have installed a newer kernel.
NEWEST_KERNEL="$(ls -1 /boot/vmlinuz-* | sort -V | tail -1 | sed 's|/boot/vmlinuz-||')"
echo "Running kernel: $(uname -r)  |  Newest installed kernel: ${NEWEST_KERNEL}"

# --- NVIDIA drivers (GPU instances only) ---
# Use --gpgpu (headless) driver: provides CUDA compute without X11/nvidia-prime
# interference. GDM runs Xorg with the dummy driver for the desktop; the NVIDIA
# GPU is used only for CUDA/PyBullet physics. The full driver's nvidia_drm
# module has kernel compatibility issues and gpu-manager/prime-switch breaks
# GDM startup on EC2.
case "${INSTANCE_TYPE}" in
  g4dn*|g5*|g6*)
    apt-get -y install "linux-headers-${NEWEST_KERNEL}" build-essential dkms
    apt-get -y install ubuntu-drivers-common
    ubuntu-drivers install --gpgpu
    # --gpgpu omits nvidia-utils (nvidia-smi); detect the driver series and add it.
    NVIDIA_VER="$(dpkg -l 'nvidia-dkms-*-server' 2>/dev/null \
      | awk '/^ii/{print $2}' | head -1 | sed -n 's/.*-\([0-9]\+\)-.*/\1/p' || true)"
    echo "Detected NVIDIA driver series: ${NVIDIA_VER:-<none>}"
    if [ -n "${NVIDIA_VER}" ]; then
      apt-get -y install "nvidia-utils-${NVIDIA_VER}-server" || \
        apt-get -y install "nvidia-utils-${NVIDIA_VER}" || \
        echo "WARNING: nvidia-utils install failed for series ${NVIDIA_VER}"
    else
      # Fallback: install whatever nvidia-utils is available matching the kernel module
      echo "Fallback: searching for any nvidia-utils package..."
      FALLBACK="$(apt-cache search '^nvidia-utils-[0-9]' 2>/dev/null | awk '{print $1}' | sort -V | tail -1 || true)"
      if [ -n "${FALLBACK}" ]; then
        echo "Installing ${FALLBACK}"
        apt-get -y install "${FALLBACK}" || echo "WARNING: ${FALLBACK} install failed"
      fi
    fi
    dkms autoinstall -k "${NEWEST_KERNEL}" || true
    # Verify nvidia-smi is on PATH now
    if command -v nvidia-smi &>/dev/null; then
      echo "nvidia-smi found at: $(command -v nvidia-smi)"
    else
      echo "WARNING: nvidia-smi still not found after driver install"
      ls -la /usr/bin/nvidia-smi /usr/lib/nvidia/bin/nvidia-smi 2>/dev/null || true
    fi
    ;;
  *)
    echo "Skipping NVIDIA packages (instance type: ${INSTANCE_TYPE:-unknown})."
    ;;
esac

# --- Desktop environment ---
# GDM runs in Xorg mode (Wayland disabled) with the xf86-video-dummy driver.
# The EC2 virtual VGA (simple-framebuffer) is locked at 800x600; the dummy
# driver provides a 1920x1080 virtual framebuffer so DCV can stream at full
# resolution. CUDA/PyBullet physics still runs on the NVIDIA GPU.
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install ubuntu-desktop-minimal
apt-get -y install xserver-xorg-video-dummy
systemctl set-default graphical.target

# Xorg dummy driver config: default 1920x1080, up to 4K (256 MB VRAM)
cat > /etc/X11/xorg.conf << 'XORGEOF'
Section "Device"
    Identifier  "DummyDevice"
    Driver      "dummy"
    VideoRam    256000
EndSection

Section "Monitor"
    Identifier  "DummyMonitor"
    HorizSync   28.0-80.0
    VertRefresh 48.0-75.0
    Modeline "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync
    Modeline "1600x900_60.00"  118.25 1600 1696 1856 2112  900  903  908  934 -hsync +vsync
    Modeline "1280x720_60.00"   74.50 1280 1344 1472 1664  720  723  728  748 -hsync +vsync
EndSection

Section "Screen"
    Identifier  "DummyScreen"
    Device      "DummyDevice"
    Monitor     "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080_60.00" "1600x900_60.00" "1280x720_60.00"
        Virtual 4096 2160
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier  "DummyLayout"
    Screen      "DummyScreen"
EndSection
XORGEOF

# Disable Wayland — force GDM to use Xorg so the dummy driver provides the display
if grep -q '^#WaylandEnable=false' /etc/gdm3/custom.conf; then
  sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
elif ! grep -q '^WaylandEnable=false' /etc/gdm3/custom.conf; then
  sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
fi

# --- Build tools, Python, and utilities ---
apt-get -y install \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  gcc \
  g++ \
  make \
  git \
  libgl1 \
  libgomp1 \
  curl \
  wget \
  unzip \
  ca-certificates \
  apt-transport-https \
  gnupg \
  mesa-utils \
  ffmpeg \
  xdg-utils \
  dbus-x11

# --- Visual Studio Code (desktop; use inside DCV / GNOME — Path A) ---
install -d /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
chmod a+r /etc/apt/keyrings/packages.microsoft.gpg
printf '%s\n' 'deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main' > /etc/apt/sources.list.d/vscode.list
apt-get update
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install code

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
  "boto3" \
  "Pillow" \
  "matplotlib"
chown -R ubuntu:ubuntu "${VENV}"
if ! grep -q 'pybullet-venv' /home/ubuntu/.bashrc 2>/dev/null; then
  echo "source ${VENV}/bin/activate" >> /home/ubuntu/.bashrc
fi

# --- DCV config ---
if [ -f /etc/dcv/dcv.conf ]; then
  # Automatic console session
  if ! grep -qF '[session-management/automatic-console-session]' /etc/dcv/dcv.conf; then
    printf '\n[session-management/automatic-console-session]\n' >> /etc/dcv/dcv.conf
  fi
  if ! grep -qF 'owner="ubuntu"' /etc/dcv/dcv.conf; then
    sed -i '/^\[session-management\/automatic-console-session\]/a owner="ubuntu"\nstorage-root="%home%"' /etc/dcv/dcv.conf
  fi
  sed -i 's/^#create-session/create-session/g' /etc/dcv/dcv.conf || true

  # Display: allow the web client to resize up to 4K and auto-adapt to the
  # browser window size instead of being stuck at a small fixed resolution.
  if ! grep -qF '[display]' /etc/dcv/dcv.conf; then
    printf '\n[display]\n' >> /etc/dcv/dcv.conf
  fi
  # Remove any existing values we are about to set (idempotent re-runs)
  sed -i '/^web-client-max-head-resolution/d; /^max-head-resolution/d; /^enable-client-resize/d; /^console-session-default-layout/d' /etc/dcv/dcv.conf
  sed -i '/^\[display\]/a web-client-max-head-resolution=(4096, 2160)\nmax-head-resolution=(4096, 2160)\nenable-client-resize=true' /etc/dcv/dcv.conf
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
source "${VENV}/bin/activate" && python3 -c "import pybullet as p; c=p.connect(p.DIRECT); p.disconnect(); print('PyBullet: OK')" 2>/dev/null || echo "PyBullet: import failed"
code --version 2>/dev/null | head -1 || echo "VS Code: not found"
echo "=== Provision complete ==="
