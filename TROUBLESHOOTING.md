# Troubleshooting

Common issues and how to fix them. All commands assume you're in the `infrastructure/` directory unless noted otherwise.

---

## Sim runners (SSM) — quick reference

| Situation | What to know |
|-----------|----------------|
| **Stale `tofu output` for instance id** | Outputs can lag after the EC2 resource is gone. Scripts use **`describe-instances`** instead of trusting output alone where it matters. |
| **Stopped vs terminated** | **Stopped:** start again or let precheck/start scripts bring it up. **Terminated:** need a new instance from **`tofu apply`**. |
| **Wrong host** | The **Packer** builder instance is tagged **`…-packer-builder`**. The workstation you want is **`…-pybullet`**. |
| **`AWS-RunShellScript`** | Uses **`/bin/sh`** — remote one-liners must not use **`set -o pipefail`** ( **`run-pybullet-s3-sim-test.sh`** follows this ). |

---

## Acceptance script warns: nvidia-smi failed on a GPU instance

The AMI may have been built when a different kernel was “newest” than the one that booted at runtime, so DKMS modules might not load. Rebuild the golden AMI (`tofu apply` after changing the provision script) or replace the instance: `tofu apply -auto-approve -replace='module.pybullet_host.aws_instance.this'`. To **fail** the acceptance run when `nvidia-smi` is missing, run `STRICT_ACCEPTANCE_GPU=1 ./scripts/run-acceptance.sh` (or export the variable before `scripts/acceptance/on-instance-checks.sh` on the instance).

---

## Acceptance script hangs on "Waiting for SSM agent"

`scripts/run-acceptance.sh` defaults to `AWS_PROFILE=personal`. If your credentials use another profile, run `AWS_PROFILE=yourprofile ./scripts/run-acceptance.sh`. Ensure the instance has the SSM IAM policy and that `aws ssm describe-instance-information` lists the instance as **Online**.

---

## DCV: "This site can't be reached" / connection timeout

**1. Check the instance's current public IP** (it changes on stop/start):

```bash
tofu output -raw pybullet_host_public_ip
```

**2. Make sure your IP is allowed in the security group.** The SG auto-locks to the IP that ran `tofu apply`. If your IP changed, just re-apply:

```bash
tofu apply -auto-approve
```

You can check your current IP with:

```bash
curl -fsS https://checkip.amazonaws.com
```

**3. Verify DCV is running** (connect via SSM first):

```bash
sudo systemctl status dcvserver --no-pager
sudo ss -tlnp | grep 8443
```

**4. Test the connection from your machine:**

```bash
curl -vk --connect-timeout 8 "https://PUBLIC_IP:8443/"
```

If you see `Connected` — the path is open (certificate warnings are normal). If `timed out` or `refused` — it's a network or service issue.

---

## DCV: "Wrong username or password"

- Username must be exactly **`ubuntu`**. Not `ssm-user`, not `root`.
- The password is whatever you set with `sudo passwd ubuntu` **on the instance** via SSM.
- The EC2 SSH key pair has nothing to do with the DCV login.
- Quick check: `sudo passwd --status ubuntu` — look for `P` (password is set and usable).

---

## DCV: stuck on "Connecting..." (spinner after login)

This means DCV is up (port 8443 is responding) but it can't attach to a desktop session.

**1. Check the services:**

```bash
sudo systemctl status dcvserver --no-pager
sudo systemctl status gdm --no-pager
sudo dcv list-sessions 2>/dev/null || true
```

**2. Restart them** (this often fixes GDM/DCV timing issues):

```bash
sudo systemctl restart gdm
sleep 20
sudo systemctl restart dcvserver
```

**3. If `journalctl -u gdm` shows "maximum number of X display failures"** — NVIDIA drivers are missing or broken. Fix:

```bash
sudo apt-get -y install linux-headers-$(uname -r) build-essential dkms ubuntu-drivers-common
sudo ubuntu-drivers install --gpgpu
sudo reboot
```

After reboot, verify with `nvidia-smi`.

---

## OpenTofu: `ParameterNotFound`

The SSM parameter for the golden AMI doesn't exist yet. This happens on the very first deploy. Fix:

```bash
tofu apply -auto-approve -target=null_resource.packer_pybullet_ami[0]
tofu apply -auto-approve
```

Or skip Packer entirely by setting `packer_ami_id_override` in `local.tf` to an existing AMI id.

---

## OpenTofu: "Packer needs a subnet with internet access"

`local.packer_subnet_id` resolved to null. Either:
- Set `ec2_subnet_id` explicitly in `local.tf`, or
- Make sure a subnet in your VPC has a `Name` tag containing `public`

---

## SSM: instance shows "Offline"

- The instance needs to reach AWS SSM over HTTPS (port 443). That means a public subnet with an internet gateway, or a private subnet with NAT + VPC endpoints.
- The IAM role already includes `AmazonSSMManagedInstanceCore`.
- Give it a few minutes after launch for the agent to register.
- For private subnets, see [SSM VPC endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html).

---

## Replacing the instance after a new AMI build

If a new Packer build ran and you want to force the instance to use the new AMI:

```bash
tofu apply -auto-approve -replace='module.pybullet_host.aws_instance.this'
```

---

## Quick AWS CLI sanity check

Make sure your credentials are working:

```bash
aws sts get-caller-identity --profile personal
```

---

## PyBullet recording: motion looks like “head only”

The GIF is whatever `run-pybullet-s3-sim-test.sh` pushed to S3 in that run. Older builds drove unnamed joints as “body” and the dome dominated. Update the repo, rerun `./scripts/run-pybullet-s3-sim-test.sh`, and download again with `./scripts/download-pybullet-sim-recording.sh "$(./scripts/list-pybullet-sim-recordings.sh --uris-only | head -1)"`. If you hand-edit the Python on the instance, SSM will not pick that up until you change the workstation copy and rerun the runner.

---

## Download script wrote nowhere useful / file not under `recordings/`

By default, `download-pybullet-sim-recording.sh` creates **`recordings/<basename>`** next to the repo root. A bare second argument such as `my.gif` also goes under `recordings/`. Only a path with `/` (relative to repo root) or an absolute path overrides that. For the newest upload: `./scripts/list-pybullet-sim-recordings.sh --uris-only | head -1`.

If you still have old **`latest-*.gif`** files at the repository root from earlier iterations, you can delete them; current tooling expects ad-hoc pulls under **`recordings/`** (the sample **`recordings/r2d2_plane_sim.gif`** is meant to stay for the README).

---

## OpenTofu: `Invalid index` / `null_resource.packer_pybullet_ami[0]` not found

`packer_ami_id_override` is set in `infrastructure/local.tf`, so the Packer `null_resource` has **count 0** and the `[0]` index does not exist. Either set **`packer_ami_id_override = null`** and use the README first-time `-target=…[0]` flow, or drop the `-target` and apply with the pinned AMI only.

---

## Cleared `packer_ami_id_override` and the next apply wants a full Packer build

That is normal: with **`null`**, OpenTofu wires the EC2 AMI to SSM, and the `null_resource` runs Packer when triggers change. Budget 30–60+ minutes. If a golden AMI is already in SSM and you only need a fresh instance from it, you can `tofu apply -auto-approve -replace='module.pybullet_host.aws_instance.this'` **after** the parameter exists — but changing provisioner files still triggers a rebuild when override is null.

---

## Workstation: `aws s3 cp` denied on sim GIFs

The instance role can **PutObject** on `sim-runs/*`; your laptop profile needs **`s3:GetObject`** (and `ListBucket` on the prefix) on the **`pyb-sim-<region>-<account-id>`** bucket to run `download-pybullet-sim-recording.sh`. PowerUser/Administrator covers it; tighter policies should allow read on that bucket or prefix.


---

## OpenTofu state looks inconsistent after interrupted apply

If `tofu state list` is missing `module.pybullet_host.aws_instance.this` but `tofu output -raw pybullet_host_instance_id` still prints an id, don’t trust that id—it may be a ghost.

What usually works: confirm what actually exists with `aws ec2 describe-instances`, then run a full `tofu apply -auto-approve` so OpenTofu recreates the instance from the module. If you’re also renaming the S3 bucket, expect Terraform to **destroy** the old bucket resource; AWS will refuse if the bucket still has objects (`BucketNotEmpty`). Empty it first, e.g. `aws s3 rm s3://OLD_BUCKET/ --recursive`, then apply again.

If Packer’s `null_resource` exits with **Install Packer** or **`packer` not found**, the OpenTofu `local-exec` runs in your normal shell—install Packer and put it on **`PATH`**, same as for a manual `packer build`.

Rare: Packer prints progress, creates an AMI, then the parent `tofu`/`packer` process sits there doing nothing. The AMI may already be **available** in EC2 while the CLI is stuck. Check the AWS console (or `aws ec2 describe-images --owners self`), then put that AMI id into SSM with `aws ssm put-parameter --overwrite` on `/pybullet/aws-pybullet-environment/golden-ami-id`, `tofu untaint null_resource.packer_pybullet_ami[0]` if it was tainted, and continue with apply—only if you’re sure the build actually finished.

---

## `./scripts/…`: Permission denied

The repo expects workstation scripts to be executable. Some filesystems or archive steps strip the bit. Fix once:

```bash
chmod +x scripts/run-acceptance.sh scripts/run-pybullet-s3-sim-test.sh \
  scripts/stop-pybullet-host.sh scripts/list-pybullet-sim-recordings.sh \
  scripts/download-pybullet-sim-recording.sh scripts/acceptance/on-instance-checks.sh
```

Or run with `bash scripts/foo.sh`—same behavior.

---

## S3: `BucketNotEmpty` when OpenTofu replaces the sim bucket

Renaming the bucket in code forces replace: destroy old, create new. AWS won’t delete a bucket that still has keys. Empty the old bucket (`aws s3 rm s3://BUCKET/ --recursive`), then re-run `tofu apply -auto-approve`. The config sets **`force_destroy`** on the new bucket so future teardowns are less painful, but the object delete step is still on you during migration.

---

## NVIDIA driver: `nvidia-smi` not found (GPU instance)

**Symptom:** Instance runs on g5/g4dn/g6 and `nvidia-smi` returns "command not found", but CUDA workloads may still work.

**Root cause:** `ubuntu-drivers install --gpgpu` installs the headless driver (`nvidia-headless-XXX-server` + `nvidia-dkms-XXX-server`) which omits `nvidia-utils-XXX-server` — the package containing `nvidia-smi`.

**Fix on a running instance** (pick the version matching your loaded driver, check with `dkms status` or `cat /proc/driver/nvidia/version`):

```bash
sudo apt install nvidia-utils-590-server   # or whichever series matches
```

**Fix in the Packer provision script** (`packer/scripts/provision-ubuntu.sh`): after `ubuntu-drivers install --gpgpu`, detect the installed driver series and install the matching utils:

```bash
NVIDIA_VER="$(dpkg -l 'nvidia-dkms-*-server' 2>/dev/null \
  | awk '/^ii/{print $2}' | head -1 | grep -oP '\d+' | head -1 || true)"
if [ -n "${NVIDIA_VER}" ]; then
  apt-get -y install "nvidia-utils-${NVIDIA_VER}-server" || \
    apt-get -y install "nvidia-utils-${NVIDIA_VER}"
fi
```

The Packer HCL post-reboot sanity check should **not** use `|| echo 'WARN…'` for `nvidia-smi` on known GPU builders — let it fail the build so broken AMIs aren't baked.

---

## NVIDIA driver: full driver vs headless (`--gpgpu`) — what to use

**Use `--gpgpu` (headless).** Do not use `ubuntu-drivers install` (full driver) on EC2 GPU instances with Ubuntu 24.04 + kernel 6.17+.

**What went wrong with the full driver (tested May 2026):**

1. `ubuntu-drivers install` (no `--gpgpu`) installs the full NVIDIA driver which pulls in `nvidia-prime`, `gpu-manager`, and the X11 nvidia DDX driver.
2. The `nvidia_drm` kernel module fails to load: `nvidia_drm: Unknown symbol drm_fbdev_ttm_driver_fbdev_probe (err -2)` — a kernel 6.17 / driver API mismatch.
3. Without `nvidia_drm`, `gpu-manager` loops forever looking for `/run/u-d-c-nvidia-drm-was-loaded`, blocking GDM startup entirely.
4. With `WaylandEnable=false`, GDM tries Xorg with the nvidia driver, which also fails: `Cannot run in framebuffer mode. Please specify busIDs for all framebuffer devices`.
5. With Wayland enabled, `gpu-manager`/`prime-switch` still blocks GDM before Mutter can start.
6. Net result: **no desktop at all** — DCV shows "Connecting…" forever.

**How to recover a broken instance** (if you accidentally deployed with the full driver):

```bash
# Via SSM RunShellScript or SSM session:
sudo systemctl stop gdm
sudo systemctl stop dcvserver
sudo rm -f /etc/X11/xorg.conf
sudo apt-get -y remove nvidia-prime ubuntu-drivers-common
sudo apt-get -y autoremove
sudo touch /run/u-d-c-nvidia-drm-was-loaded
sudo systemctl start gdm
sleep 15
sudo systemctl start dcvserver
```

Verify: `ps aux | grep gnome-shell` should show Mutter running. `nvidia-smi` still works for CUDA compute.

**Why headless works:** The `--gpgpu` driver provides CUDA/compute support without X11 or nvidia-prime interference. GDM/Mutter starts with Wayland and uses software rendering (llvmpipe) for the desktop compositor, while CUDA/PyBullet physics runs on the GPU. DCV captures the Wayland desktop via its console session.

---

## DCV: desktop resolution stuck at 800x600 (won't scale to browser window)

**Status: RESOLVED — Xorg dummy driver approach.**

**Symptom:** After logging in via DCV web client, the GNOME desktop appears in a small 800x600 box that doesn't stretch to fill the browser window, regardless of browser size.

**Root cause:** The EC2 virtual VGA adapter (Amazon Device 1111) uses the `simple-framebuffer` kernel driver, which is locked to the firmware-set boot resolution of 800x600. Neither Wayland/Mutter nor Xorg's modesetting driver can change it because `simpledrm` doesn't support modesetting. The `bochs-drm` kernel module (which would enable proper modesetting) is not available in the AWS kernel (`6.17.0-1013-aws`).

**Solution (applied in provision script):** Install `xserver-xorg-video-dummy` and create `/etc/X11/xorg.conf` with a 1920x1080 virtual framebuffer (256 MB VRAM). Disable Wayland in GDM so Xorg uses the dummy driver instead of the locked simpledrm. DCV then captures and streams the 1920x1080 framebuffer.

Key changes:
1. `apt-get install xserver-xorg-video-dummy`
2. Create `/etc/X11/xorg.conf` with dummy driver at 1920x1080
3. Set `WaylandEnable=false` in `/etc/gdm3/custom.conf`
4. DCV `[display]` settings in `dcv.conf` for client resize support

Verify on a running instance:
```bash
grep -i layout /var/log/dcv/server.log | tail -3
# Should show: size 1920x1080
```

**Approaches that did NOT work:**

- **Mutter D-Bus API** (`ApplyMonitorsConfig`): D-Bus call returns success but `simpledrm` can't actually change the hardware resolution, so it stays at 800x600.
- **monitors.xml** (for GDM and user): Same issue — Mutter reads the config but the DRM backend can't apply the mode.
- **DCV virtual sessions** (`--type virtual`): `dcvagent` segfaults in `libX11-xcb.so` / `libxcb.so` on Ubuntu 24.04 with DCV 2025.0. The virtual session starts but crashes within ~2 seconds.
- **bochs-drm kernel module**: Not available in the AWS kernel.
- **Full NVIDIA driver** (non-headless): `nvidia_drm` has kernel compatibility issues on 6.17; `gpu-manager` loops and blocks GDM startup.

**Debugging commands** (run via SSM on the instance):

```bash
# Check what display resolution DCV sees
grep -i layout /var/log/dcv/server.log | tail -5

# Check Xorg is using the dummy driver
grep -i dummy /var/log/Xorg.0.log | head -5

# Check DCV agent resize attempts
grep -i "resize\|layout" /var/log/dcv/agent.ubuntu.console.log | tail -10

# Check for segfaults (virtual session debugging)
dmesg | grep -i segfault | tail -10

# Check DCV config
grep -A5 "\[display\]" /etc/dcv/dcv.conf
```

---

## Rebuilding the AMI from scratch (delete old AMI + instance)

When you need a clean AMI rebuild (e.g. after changing the provision script):

```bash
# 1. Stop the instance
./scripts/stop-pybullet-host.sh --wait

# 2. Get current AMI and instance IDs
cd infrastructure
AMI_ID="$(tofu output -raw pybullet_golden_ami_id)"
INSTANCE_ID="$(tofu output -raw pybullet_host_instance_id)"
REGION="$(tofu output -raw aws_region)"

# 3. Deregister the AMI and delete its snapshots
SNAP_IDS=$(aws ec2 describe-images --image-ids "$AMI_ID" --region "$REGION" \
  --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' --output text --profile personal)
aws ec2 deregister-image --image-id "$AMI_ID" --region "$REGION" --profile personal
for snap in $SNAP_IDS; do
  aws ec2 delete-snapshot --snapshot-id "$snap" --region "$REGION" --profile personal
done

# 4. Terminate the instance and delete the SSM parameter
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --profile personal
aws ssm delete-parameter --name "/pybullet/aws-pybullet-environment/golden-ami-id" \
  --region "$REGION" --profile personal

# 5. Remove from tofu state so it rebuilds
tofu state rm 'null_resource.packer_pybullet_ami[0]'
tofu state rm 'module.pybullet_host.aws_instance.this'

# 6. Rebuild (runs Packer + creates new instance — takes 30-60+ minutes)
tofu apply -auto-approve
```
