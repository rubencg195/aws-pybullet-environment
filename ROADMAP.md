# Roadmap

This file tracks what's been done and what's coming next. Each phase builds on the previous one.

**Status labels:** DONE | PARTIAL | NOT STARTED

---

## Phase 0 — AL2023 Baseline (DONE)

The current working stack. Everything here is deployed and verified.

| # | What | Status |
|---|------|--------|
| 0.1 | Packer golden AMI: AL2023 + NVIDIA + GNOME + DCV 2025.0 + PyBullet venv | DONE |
| 0.2 | OpenTofu → Packer → SSM Parameter Store → EC2 pipeline | DONE |
| 0.3 | EC2 module: SG (SSH + DCV), IAM (SSM), IMDSv2, gp3, public IP | DONE |
| 0.4 | DCV pinned tarball + SHA256 verification | DONE |
| 0.5 | Golden AMI id published to SSM; OpenTofu reads it automatically | DONE |
| 0.6 | `packer_ami_id_override` to skip Packer during dev | DONE |
| 0.7 | `.gitattributes` LF enforcement for .tf, .pkr.hcl, .sh | DONE |
| 0.8 | `.gitignore` for `packer-manifest.json` | DONE |
| 0.9 | Fix: Packer `execute_command` — provision script now runs with sudo | DONE |
| 0.10 | Fix: IMDSv2 token-based metadata retrieval (was IMDSv1, silently skipped NVIDIA) | DONE |
| 0.11 | Fix: DCV auto-session hardening — creates config section if missing | DONE |
| 0.12 | Fix: kernel-devel/headers unpinned to avoid version mismatch on build | DONE |
| 0.13 | Fix: SSM parameter path changed from `/aws` (reserved) to `/pybullet` prefix | DONE |
| 0.14 | Packer `snapshot_tags`, `run_tags` for cost tracking; `ssh_timeout` for robustness | DONE |
| 0.15 | Post-reboot sanity checks: `nvidia-smi`, DCV, PyBullet import — blocks bad AMIs | DONE |
| 0.16 | Provision cleanup: DCV temp files removed, end-of-provision summary printed | DONE |
| 0.17 | EC2: root volume tagged, `delete_on_termination`, SG `create_before_destroy` | DONE |
| 0.18 | Removed legacy `user_data.sh`, reset AMI override, added output descriptions | DONE |
| 0.19 | Auto-detect public IP for SG ingress via `checkip.amazonaws.com` | DONE |
| 0.20 | Golden AMI output marked `sensitive` for SSM provider compatibility | DONE |
| 0.21 | Docs split: README (quick start) + SETUP.md + TROUBLESHOOTING.md + ROADMAP.md | DONE |
| 0.22 | Architecture + DevOps flow diagrams in README | DONE |
| 0.23 | Full destroy + recreate verified end-to-end | DONE |

---

## Phase 1 — Ubuntu LTS Golden AMI (DONE)

Migrated from Amazon Linux 2023 to Ubuntu 24.04 LTS. Full pipeline verified end-to-end.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1.1 | Create `packer/pybullet-ubuntu.pkr.hcl` | DONE | Canonical 24.04 AMI filter, `ssh_username = "ubuntu"`, `/dev/sda1` root device |
| 1.2 | Create `packer/scripts/provision-ubuntu.sh` | DONE | `apt`-based: `ubuntu-desktop-minimal`, NVIDIA via `ubuntu-drivers`, DCV `.deb`, `/opt/pybullet-venv` |
| 1.3 | NVIDIA drivers on Ubuntu | DONE | `ubuntu-drivers install --gpgpu` + DKMS autoinstall against newest kernel |
| 1.4 | DCV for Ubuntu | DONE | Ubuntu 24.04 `.deb` packages (`nice-dcv-ubuntu2404-x86_64.tgz`), pinned SHA256, `dcv.conf` owner = `ubuntu` |
| 1.5 | Wire `infrastructure/packer.tf` to new template | DONE | Triggers point to `pybullet-ubuntu.pkr.hcl` and `provision-ubuntu.sh` |
| 1.6 | Update all `ec2-user` references to `ubuntu` | DONE | `dcv.conf`, `.bashrc`, README, TROUBLESHOOTING.md, SETUP.md |
| 1.7 | SSM agent on Ubuntu | DONE | Preinstalled on Canonical Ubuntu 24.04 AMIs; verified working |
| 1.8 | End-to-end Packer build + deploy | DONE | AMI `ami-0b3df7a8e60df839f`, ~31 min build, verified DCV + PyBullet + SSM |

### Issues fixed during migration

| Issue | Fix |
|-------|-----|
| Duplicate Packer variable error (both `.pkr.hcl` files in same dir) | `packer init` targets specific file instead of `.` |
| `ubuntu-desktop-minimal` install failed silently | Suppressed `needrestart` interactive prompts with `NEEDRESTART_MODE=a` and config |
| `libgl1-mesa-glx` removed in Ubuntu 24.04 | Replaced with `libgl1` |
| `nvidia-utils-570` conflicted with `ubuntu-drivers` (installed 595) | Removed hardcoded version — let `ubuntu-drivers` handle everything |
| NVIDIA DKMS modules not built for post-upgrade kernel | Install headers for newest kernel + `dkms autoinstall -k` against it |
| Dpkg config prompts during upgrade | Added `--force-confdef --force-confold` to all `apt-get` calls |
| Packer SSH timeout during long installs | Added `ssh_read_write_timeout = "30m"` to template |

---

## Phase 2 — VS Code (DONE)

> **Path A** chosen: desktop **Visual Studio Code** inside GNOME over DCV (no extra security group port).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 2.1 | Choose install path | DONE | Path A: Microsoft `code` package via official apt repo |
| 2.2 | Install in Packer provisioner | DONE | `provision-ubuntu.sh`: keyring + `vscode.list` + `apt-get install code`; post-reboot `code --version` in Packer |
| 2.3 | SG for code-server (Path B only) | N/A | Path B not used; no TCP 8080 |

---

## Phase 3 — Quality and Testing (DONE)

> **Priority: MEDIUM**

| # | Task | Status | Notes |
|---|------|--------|-------|
| 3.1 | External smoke test after AMI build | DONE | `scripts/run-acceptance.sh` curls DCV URL (TLS, `-k`) from workstation; use `--skip-external` if SG blocks your IP |
| 3.2 | Slim golden image variant | DEFERRED | Optional cost/size win; needs a separate provision path or template (risk of breaking GNOME/DCV). Not required for Phase 3 exit |
| 3.3 | Acceptance test script | DONE | `scripts/acceptance/on-instance-checks.sh` + `scripts/run-acceptance.sh`: required checks above; GPU `nvidia-smi` warns unless `STRICT_ACCEPTANCE_GPU=1` |

---

## Phase 4 — Production Hardening

> **Priority: LOW** — For shared/team use, not blocking individual dev.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 4.1 | Dedicated Packer IAM role | NOT STARTED | Least-privilege for EC2 build + SSM PutParameter |
| 4.2 | AMI / snapshot lifecycle | NOT STARTED | Auto-deregister old AMIs, cost alerts |
| 4.3 | CI/CD for Packer builds | NOT STARTED | GitHub Actions or CodeBuild |
| 4.4 | SSM parameter hardening | NOT STARTED | `SecureString` with KMS |
| 4.5 | Builder vs runtime instance type alignment | NOT STARTED | Document driver compatibility |
| 4.6 | Root device mapping validation | NOT STARTED | Validate `/dev/xvda` across OS versions |
| 4.7 | Optional container runtime | NOT STARTED | Docker/ECR only if needed |

---

## Development Guide

### Where to start

1. **Deploy** — `cd infrastructure && tofu apply -auto-approve`
2. **Acceptance tests** — from repo root: `./scripts/run-acceptance.sh` (SSM + optional external DCV curl)
3. **Manual** — DCV login, `nvidia-smi`, PyBullet, VS Code from GNOME

### Key files

- `infrastructure/local.tf` — all configurable settings
- `infrastructure/packer.tf` — how Packer integrates with OpenTofu
- `packer/pybullet-ubuntu.pkr.hcl` — Ubuntu 24.04 AMI builder (active)
- `packer/scripts/provision-ubuntu.sh` — Ubuntu provisioner (active)
- `packer/pybullet-al2023.pkr.hcl` — AL2023 AMI builder (legacy reference)
- `packer/scripts/provision-al2023.sh` — AL2023 provisioner (legacy reference)
- `packer/scripts/publish-ami-ssm.sh` — SSM publish script (shared by both templates)
- `scripts/run-acceptance.sh` — Phase 3 orchestrator (SSM + external DCV smoke)
- `scripts/acceptance/on-instance-checks.sh` — on-instance checks (invoked by runner)
- `infrastructure/modules/ec2-instance/sg.tf` — security group rules

### Open design decisions

1. **Desktop environment** — `ubuntu-desktop-minimal` (current) vs individual GNOME packages (`gdm3`, `gnome-session`, `gnome-terminal`) for faster/lighter builds
2. **VS Code path** — Path A chosen (Microsoft apt `code`). Path B (`code-server` on :8080) still available if needed later.
3. **Keep AL2023 files?** — Keep as reference or remove to reduce clutter

### Acceptance criteria

The stack is complete when all of these are true:

| # | Criterion |
|---|-----------|
| T1 | Ubuntu LTS on the golden AMI and running EC2 instance |
| T2 | GPU available (`nvidia-smi` works) |
| T3 | NICE DCV reachable at `https://<public-ip>:8443` |
| T4 | PyBullet importable in `/opt/pybullet-venv` |
| T5 | VS Code usable from the remote environment (Path A: `code` package baked in AMI) |
| T6 | OpenTofu provisions from SSM-stored AMI id |
| T7 | SSM Session Manager works |
| T8 | Security group allows SSH :22 and DCV :8443 |
