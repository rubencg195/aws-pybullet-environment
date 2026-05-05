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

## Phase 1 — Ubuntu LTS Golden AMI

> **Priority: HIGH** — This is the main migration that unblocks everything else.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1.1 | Create `packer/pybullet-ubuntu.pkr.hcl` | NOT STARTED | New `source_ami_filter` for Ubuntu 22.04 or 24.04, `ssh_username = "ubuntu"` |
| 1.2 | Create `packer/scripts/provision-ubuntu.sh` | NOT STARTED | `apt`-based: kernel headers, build tools, NVIDIA, GNOME, DCV `.deb`, `/opt/pybullet-venv` |
| 1.3 | NVIDIA drivers on Ubuntu | NOT STARTED | `ubuntu-drivers autoinstall` or NVIDIA CUDA repo. Validate on g5 builder |
| 1.4 | DCV for Ubuntu | NOT STARTED | Ubuntu `.deb` packages, pin URL + SHA256, `dcv.conf` owner = `ubuntu` |
| 1.5 | Wire `infrastructure/packer.tf` to new template | NOT STARTED | Update `local-exec`, `triggers`, AMI tags |
| 1.6 | Update all `ec2-user` references to `ubuntu` | NOT STARTED | `dcv.conf`, `.bashrc`, README, SSM examples |
| 1.7 | SSM agent on Ubuntu | NOT STARTED | Usually preinstalled on Canonical AMIs |

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

1. **Get the current baseline working first** — configure `local.tf`, run `tofu apply`, verify DCV + PyBullet.
2. **Phase 1.1–1.2** — Create Ubuntu Packer template alongside the AL2023 one. Don't modify the working AL2023 files.
3. **Phase 1.3–1.4** — Get NVIDIA and DCV working on Ubuntu. This is the hardest part.
4. **Phase 1.5–1.7** — Wire OpenTofu to the new template, update user references, verify SSM.
5. **Phase 2** — Pick VS Code path (recommend Path A: desktop `.deb`), install, add SG if needed.

### Key files to read first

- `infrastructure/local.tf` — all configurable settings
- `infrastructure/packer.tf` — how Packer integrates with OpenTofu
- `packer/pybullet-al2023.pkr.hcl` — current AMI builder (use as a pattern for Ubuntu)
- `packer/scripts/provision-al2023.sh` — current provisioner (reference for Ubuntu)
- `packer/scripts/publish-ami-ssm.sh` — SSM publish script (reusable as-is)
- `infrastructure/modules/ec2-instance/sg.tf` — security group rules

### Files to create for Ubuntu + VS Code

| Action | File |
|--------|------|
| Create | `packer/pybullet-ubuntu.pkr.hcl` |
| Create | `packer/scripts/provision-ubuntu.sh` |
| Modify | `infrastructure/packer.tf` (point to new template) |
| Modify | `infrastructure/modules/ec2-instance/sg.tf` (if code-server) |
| Modify | `README.md` (update user, OS references) |

### Open design decisions

1. **Ubuntu version** — 22.04 LTS (mature DCV support) vs 24.04 LTS (newer, needs DCV check)
2. **NVIDIA method** — `ubuntu-drivers autoinstall` (simpler) vs NVIDIA CUDA repo (more control)
3. **Desktop environment** — Full GNOME vs lighter DE (XFCE, MATE)
4. **VS Code path** — Desktop `.deb` inside DCV (recommended) vs browser `code-server` on :8080
5. **Keep AL2023 files?** — Keep as reference or remove to reduce clutter

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
