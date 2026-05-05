# Troubleshooting

Common issues and how to fix them. All commands assume you're in the `infrastructure/` directory unless noted otherwise.

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
