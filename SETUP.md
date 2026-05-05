# Setup Guide

Detailed installation steps for the tools needed to deploy this project. See the main [README](README.md) for the quick-start deploy instructions.

---

## IAM Permissions

The AWS CLI profile used for `tofu apply` and `packer build` needs these permissions:

- **EC2**: `RunInstances`, `TerminateInstances`, `CreateImage`, `Describe*`, `CreateTags`, snapshot APIs
- **SSM**: `PutParameter`, `GetParameter` on `arn:aws:ssm:REGION:ACCOUNT:parameter/pybullet/aws-pybullet-environment/golden-ami-id`

For development, `PowerUserAccess` or `AdministratorAccess` covers everything. For production, scope down to the specific EC2 + SSM parameter ARNs.

---

## Install Packer

Packer builds the golden AMI. You need it on the machine where you run `tofu apply`.

### Option A — Download the zip (no sudo needed)

```bash
mkdir -p ~/.local/bin
PACKER_VER="$(curl -fsS 'https://checkpoint-api.hashicorp.com/v1/check/packer?arch=amd64&os=linux' | python3 -c "import sys,json; print(json.load(sys.stdin)['current_version'])")"
cd /tmp
curl -fsSLO "https://releases.hashicorp.com/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip"
unzip -o "packer_${PACKER_VER}_linux_amd64.zip" packer -d ~/.local/bin
chmod +x ~/.local/bin/packer
rm -f "packer_${PACKER_VER}_linux_amd64.zip"
```

Make sure `~/.local/bin` is on your PATH:

```bash
grep -q '.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
packer version
```

### Option B — apt repository (requires sudo)

```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y packer
packer version
```

### Validate the Packer template

After installing, verify the template parses correctly:

```bash
cd packer
packer init .
packer validate \
  -var "region=us-east-1" \
  -var "vpc_id=vpc-YOURVALUE" \
  -var "subnet_id=subnet-YOURVALUE" \
  -var "project_name=aws-pybullet-environment" \
  -var "aws_cli_profile=personal" \
  pybullet-al2023.pkr.hcl
```

---

## Install the Session Manager Plugin

You need this to open SSM shell sessions from the CLI (`aws ssm start-session`).

> **WSL users:** Install the **Linux** plugin inside WSL. The Windows MSI won't work.

```bash
curl -fsSLo /tmp/session-manager-plugin.deb \
  https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb
sudo dpkg -i /tmp/session-manager-plugin.deb
session-manager-plugin --version
```

---

## Verify Your AWS Setup

Quick check that your credentials and profile are working:

```bash
aws sts get-caller-identity --profile personal
```

You should see your account ID and ARN. If this fails, fix your AWS CLI configuration before proceeding with the deploy.
