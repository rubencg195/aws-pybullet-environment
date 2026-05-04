# PyBullet + CUDA user-space + VS Code + code-server + Amazon DCV (Ubuntu 22.04 packages).
#
# Cross-check vs infrastructure/modules/ec2-instance/user_data.sh (Amazon Linux 2023 host):
# - user_data uses dnf + nice-dcv-amzn2023-*.rpm + GNOME/GDM + nvidia-driver-cuda on the EC2 host.
# - This image uses apt + nice-dcv-ubuntu2204-*.deb + XFCE; it does NOT replace host user_data until
#   EC2 is switched to Ubuntu (or another) + Docker and this image is pulled from ECR.
# - PyBullet venv path and pip packages match user_data (/opt/pybullet-venv, same scientific stack).
#
# NVIDIA kernel drivers are NOT inside the image: on EC2 g5.xlarge the host must load the
# GPU driver (or use a GPU-AMI) and run containers with --gpus all (NVIDIA Container Toolkit).
# CUDA image tag must stay within the driver’s supported CUDA range (see NVIDIA CUDA compatibility).
#
# syntax=docker/dockerfile:1
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH="/opt/pybullet-venv/bin:${PATH}"

# Prevent maintainer scripts from trying to start systemd units during image build.
RUN printf '#!/bin/sh\nexit 0\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    git \
    libgl1 \
    libegl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libgomp1 \
    dbus-x11 \
    xfce4 \
    xfce4-terminal \
    fonts-dejavu-core \
    procps \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Microsoft Visual Studio Code (GUI when a display is available, e.g. under DCV on the host).
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-code.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-code.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends code \
    && rm -rf /var/lib/apt/lists/*

# Amazon DCV server + web viewer + virtual sessions + GL (Ubuntu 22.04 x86_64).
# Ref: https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html
RUN wget -qO /tmp/NICE-GPG-KEY https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY \
    && gpg --batch --dearmor -o /etc/apt/trusted.gpg.d/nice-dcv.gpg /tmp/NICE-GPG-KEY \
    && rm -f /tmp/NICE-GPG-KEY

RUN bash -euo pipefail -c '\
    mkdir -p /tmp/dcv && cd /tmp/dcv \
    && wget -q https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-ubuntu2204-x86_64.tgz \
    && tar -xzf nice-dcv-ubuntu2204-x86_64.tgz \
    && shopt -s nullglob \
    && d=(nice-dcv-*-ubuntu2204-x86_64) \
    && if [ "${#d[@]}" -ne 1 ]; then echo "Expected one nice-dcv-*-ubuntu2204-x86_64 directory"; ls -la; exit 1; fi \
    && cd "${d[0]}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ./nice-dcv-server_*.deb \
        ./nice-dcv-web-viewer_*.deb \
        ./nice-xdcv_*.deb \
        ./nice-dcv-gl_*.deb \
    && cd / && rm -rf /tmp/dcv \
    && rm -rf /var/lib/apt/lists/*'

# code-server: VS Code–compatible editor in the browser (optional; START_CODE_SERVER=1).
ARG CODE_SERVER_VERSION=4.95.3
RUN wget -q "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" -O /tmp/code-server.tgz \
    && mkdir -p /opt/code-server \
    && tar -xzf /tmp/code-server.tgz -C /opt/code-server --strip-components=1 \
    && ln -sf /opt/code-server/bin/code-server /usr/local/bin/code-server \
    && rm -f /tmp/code-server.tgz

RUN python3 -m venv /opt/pybullet-venv \
    && /opt/pybullet-venv/bin/pip install --upgrade pip \
    && /opt/pybullet-venv/bin/pip install \
        "numpy>=1.22" \
        scipy \
        pybullet \
        Pillow \
        matplotlib

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && rm -f /usr/sbin/policy-rc.d

WORKDIR /workspace

EXPOSE 8080 8443

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
