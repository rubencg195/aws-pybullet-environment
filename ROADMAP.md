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

## Phase 1 — Ubuntu LTS Golden AMI (IN PROGRESS)

Migrating from Amazon Linux 2023 to Ubuntu 24.04 LTS. All files are created and wired; the Packer build has not yet completed successfully.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1.1 | Create `packer/pybullet-ubuntu.pkr.hcl` | DONE | Canonical 24.04 AMI filter, `ssh_username = "ubuntu"`, `/dev/sda1` root device |
| 1.2 | Create `packer/scripts/provision-ubuntu.sh` | DONE | `apt`-based: `ubuntu-desktop-minimal`, NVIDIA via `ubuntu-drivers`, DCV `.deb`, `/opt/pybullet-venv` |
| 1.3 | NVIDIA drivers on Ubuntu | DONE | `ubuntu-drivers install --gpgpu` (removed hardcoded `nvidia-utils-570` — was causing version mismatch with driver 595) |
| 1.4 | DCV for Ubuntu | DONE | Ubuntu 24.04 `.deb` packages (`nice-dcv-ubuntu2404-x86_64.tgz`), pinned SHA256, `dcv.conf` owner = `ubuntu` |
| 1.5 | Wire `infrastructure/packer.tf` to new template | DONE | Triggers point to `pybullet-ubuntu.pkr.hcl` and `provision-ubuntu.sh`; `packer init` targets specific file (fixed duplicate-variable error from having both `.pkr.hcl` files in same dir) |
| 1.6 | Update all `ec2-user` references to `ubuntu` | DONE | `dcv.conf`, `.bashrc`, README, TROUBLESHOOTING.md, SETUP.md |
| 1.7 | SSM agent on Ubuntu | DONE | Preinstalled on Canonical Ubuntu 24.04 AMIs |
| 1.8 | End-to-end Packer build + deploy | PENDING | **See known issues below** |

### Known issues to fix before next build

1. **Packer build did not complete** — the build ran for ~11 minutes and failed during the `ubuntu-desktop-minimal` apt install (828 packages). The terminal output was truncated at ~1 MB so the actual error was not captured. Likely causes:
   - The massive `ubuntu-desktop-minimal` install may trigger a `systemctl` call that fails under Packer's SSH session (e.g., `deb-systemd-invoke` errors seen in logs). Combined with `set -euxo pipefail`, this could abort the script.
   - Possible SSH read timeout if the install goes quiet for too long during DKMS compilation.

2. **Fix applied but not yet tested**: removed the hardcoded `apt-get -y install nvidia-utils-570` which was pulling in nvidia-utils-580 on top of the nvidia-595-server driver that `ubuntu-drivers install --gpgpu` already set up.

3. **Duplicate Packer variable error** (fixed): both `pybullet-al2023.pkr.hcl` and `pybullet-ubuntu.pkr.hcl` live in the same `packer/` directory. Running `packer init .` picked up both files and hit duplicate variable definitions. Fixed by changing `packer init .` to `packer init pybullet-ubuntu.pkr.hcl` in `packer.tf`.

### Recommended next steps

- Re-run `tofu apply -auto-approve` and monitor the Packer build output.
- If the build fails again during `ubuntu-desktop-minimal`, consider:
  - Adding `|| true` after the apt install to tolerate non-fatal post-install script errors, then verify services work in the post-reboot sanity checks.
  - Switching from `ubuntu-desktop-minimal` to individual packages (`gdm3`, `gnome-session`, `gnome-terminal`, `nautilus`) for a lighter install.
  - Adding `ssh_read_write_timeout = "30m"` to the Packer template if SSH is timing out during long installs.
- Once the build succeeds, verify end-to-end: DCV login, `nvidia-smi`, PyBullet import, SSM session.

---

## Phase 2 — VS Code

> **Priority: HIGH** — The target development workflow needs an IDE.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 2.1 | Choose install path | NOT STARTED | **Path A**: Desktop VS Code `.deb` inside GNOME (recommended — simplest). **Path B**: `code-server` on :8080 (needs SG rule + TLS) |
| 2.2 | Install in Packer provisioner | NOT STARTED | Add to `provision-ubuntu.sh`, verify with `code --version` |
| 2.3 | SG for code-server (Path B only) | NOT STARTED | TCP 8080 in `sg.tf`, or bind localhost + SSH tunnel |

---

## Phase 3 — Quality and Testing

> **Priority: MEDIUM**

| # | Task | Status | Notes |
|---|------|--------|-------|
| 3.1 | External smoke test after AMI build | PARTIAL | In-build checks exist (post-reboot). Full test (launch throwaway instance, curl DCV) not yet done |
| 3.2 | Slim golden image variant | NOT STARTED | Minimal GPU + PyBullet + DCV without full Desktop group |
| 3.3 | Acceptance test script | NOT STARTED | Validates all criteria: DCV, PyBullet, VS Code, GPU |

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

1. **Fix the Ubuntu Packer build** — see "Known issues" in Phase 1 above. Re-run `tofu apply -auto-approve` and diagnose if it fails.
2. **Verify end-to-end** — once the build succeeds, check DCV login, `nvidia-smi`, PyBullet import, SSM session.
3. **Phase 2** — Pick VS Code path (recommend Path A: desktop `.deb`), install, add SG if needed.

### Key files

- `infrastructure/local.tf` — all configurable settings
- `infrastructure/packer.tf` — how Packer integrates with OpenTofu
- `packer/pybullet-ubuntu.pkr.hcl` — Ubuntu 24.04 AMI builder (active)
- `packer/scripts/provision-ubuntu.sh` — Ubuntu provisioner (active)
- `packer/pybullet-al2023.pkr.hcl` — AL2023 AMI builder (legacy reference)
- `packer/scripts/provision-al2023.sh` — AL2023 provisioner (legacy reference)
- `packer/scripts/publish-ami-ssm.sh` — SSM publish script (shared by both templates)
- `infrastructure/modules/ec2-instance/sg.tf` — security group rules

### Open design decisions

1. **Desktop environment** — `ubuntu-desktop-minimal` (current) vs individual GNOME packages (`gdm3`, `gnome-session`, `gnome-terminal`) for faster/lighter builds
2. **VS Code path** — Desktop `.deb` inside DCV (recommended) vs browser `code-server` on :8080
3. **Keep AL2023 files?** — Keep as reference or remove to reduce clutter

### Acceptance criteria

The stack is complete when all of these are true:

| # | Criterion |
|---|-----------|
| T1 | Ubuntu LTS on the golden AMI and running EC2 instance |
| T2 | GPU available (`nvidia-smi` works) |
| T3 | NICE DCV reachable at `https://<public-ip>:8443` |
| T4 | PyBullet importable in `/opt/pybullet-venv` |
| T5 | VS Code usable from the remote environment |
| T6 | OpenTofu provisions from SSM-stored AMI id |
| T7 | SSM Session Manager works |
| T8 | Security group allows SSH :22 and DCV :8443 |
