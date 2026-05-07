# Troubleshooting

Common issues and how to fix them. All commands assume you're in the `infrastructure/` directory unless noted otherwise.

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
