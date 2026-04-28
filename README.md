# aws-pybullet-environment

Infrastructure and tooling to run **PyBullet** physics simulation in **Amazon Web Services (AWS)**, so robotics and simulation work can be performed **remotely** from a **low-specification or portable client** (for example, a small laptop on Wi‑Fi) while the **GPU and CPU work** run on a **dedicated host in the cloud**. The goal is to separate **where you work** from **where the simulation runs**: a graphical desktop, DCV, and the PyBullet environment live on **EC2**; the client only needs a **browser** or the **NICE DCV** / **SSM** tooling.

**What is deployed today** (see `infrastructure/`): a **GPU** EC2 instance (default type **`g4dn.2xlarge`**, set in `local.tf`), **Amazon Linux 2023**, **NICE/Amazon DCV** (HTTPS on **8443**), **SSM** (no password stored in Terraform), a **security group** with CIDRs from `local.tf`, first-boot **user data** (GNOME, DCV, PyBullet in `/opt/pybullet-venv`), and helper scripts under **`src/ssm-ec2-inital-setup/`** to open an **SSM** session so you can set **`ec2-user`**’s password for DCV. The VPC is selected by the **`Name`** tag (`local.vpc_name` in `local.tf` → `data.aws_vpc` in `data.tf`).

## Architecture (overview)

```mermaid
flowchart LR
  subgraph client["Client (low-spec or mobile)"]
    B["Web browser or DCV client"]
  end
  subgraph aws["AWS"]
    DCV["NICE DCV :8443"]
    EC2["EC2 g4dn / PyBullet workload"]
  end
  B -->|TLS| DCV
  DCV --> EC2
```

## Architecture (detailed)

```mermaid
flowchart TB
  subgraph iac["Infrastructure as code"]
    TF["Terraform in infrastructure/"]
  end
  subgraph net["VPC by Name tag"]
    SG["Security group: SSH, DCV"]
  end
  subgraph compute["Compute"]
    AL2023["Amazon Linux 2023 AMI"]
    UD["user_data: Desktop + DCV + PyBullet venv"]
    G4["Instance: g4dn.2xlarge (NVIDIA T4 class)"]
  end
  subgraph access["Access"]
    SSM["IAM: SSM Session Manager"]
  end
  TF --> G4
  G4 --> AL2023
  G4 --> SG
  G4 --> UD
  G4 --> SSM
```

## Repository layout

| Path | Purpose |
|------|--------|
| `infrastructure/provider.tf` | AWS provider, **S3 backend** (state); align **`profile`** with your CLI profile. |
| `infrastructure/local.tf` | **Instance** settings, **`allowed_ingress_cidrs`**, **`vpc_name`** (must match the VPC’s **`Name`** tag in EC2), etc. |
| `infrastructure/data.tf` | `data.aws_vpc` (by **`local.vpc_name`**) and account/region data. |
| `infrastructure/compute.tf` | Wires the **ec2-instance** module. |
| `infrastructure/outputs.tf` | **Public IP**, instance id, **region** (SSM/CLI helpers). |
| `infrastructure/modules/ec2-instance` | IAM (SSM), security group, instance, `user_data.sh` |
| `src/ssm-ec2-inital-setup/ssm-connect.sh`, `ssm-connect.ps1` | **WSL** / **Windows** helpers for `aws ssm start-session` using outputs from `infrastructure/`. |
| `src/` (other) | Application and simulation code (to be expanded). |

## Security: instance ingress

`infrastructure/local.tf` sets `allowed_ingress_cidrs`. If that list is **empty**, Terraform uses **`0.0.0.0/0`**, so **any** public IPv4 can reach **TCP 22** (SSH) and **TCP 8443** (NICE DCV).

That is convenient for a first test but **not** appropriate for a long-lived or sensitive system. For routine use, set **`allowed_ingress_cidrs`** to your public IP as **`["x.x.x.x/32"]`**, and update it when your address changes, or use a **VPN** / **bastion** with a stable CIDR. **SSM** does *not* require you to open SSH to the world: your **AWS CLI** uses the SSM service; the instance only needs **outbound HTTPS to AWS** (the default security group allows this).

## Prerequisites

- An **AWS account** and a **named CLI profile** (examples below use `personal`; it must match **`profile`** in `infrastructure/provider.tf` or export **`AWS_PROFILE`**).
- The **HashiCorp Terraform** CLI (examples use **`terraform`**; **OpenTofu** users can substitute **`tofu`**) and **AWS CLI v2** with the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) if you will use SSM.
- In **`infrastructure/local.tf`**, set **`vpc_name`** to the **`Name` tag** of the VPC you use. If `terraform apply` cannot find a VPC, add or correct that tag in the AWS console for that VPC.

## Deploy the stack

From the **`infrastructure/`** directory (the directory that contains `provider.tf` and state or backend config):

```bash
cd infrastructure
terraform init
terraform plan
terraform apply -auto-approve
```

If you use **OpenTofu**, run the same with **`tofu`** instead of **`terraform`**. Ensure your backend in **`provider.tf`** (S3 bucket, key, **profile**, region) is valid for your account.

**Useful outputs** (run from `infrastructure/` after apply):

| Output | Use |
|--------|-----|
| `terraform output -raw pybullet_host_dcv_url` | **DCV in the browser** — full `https://…:8443` (best for copy or clickable links) |
| `terraform output -raw pybullet_host_public_ip` | Public IPv4 only |
| `terraform output -raw pybullet_host_instance_id` | **SSM** target, EC2 console |
| `terraform output -raw pybullet_host_subnet_id` | **Subnet** the instance is in (check **public** / route table in console if SSM is offline) |
| `terraform output -raw aws_region` | **Region** for CLI commands |

**First boot:** user data may take **a long time** (desktop packages, DCV, reboot). Wait until the instance is **Running**; if the URL does not load yet, wait a few more minutes. **SSM** may show **Online** only after a short delay; see **EC2 → Systems Manager → Fleet Manager**.

## After deploy: use NICE / Amazon DCV

Follow these in order the first time.

1. **Ingress**  
   If you restricted `allowed_ingress_cidrs`, your **current** public IP must be included, or the browser will not reach **8443** (or SSH **22**). You can re-apply after editing `local.tf`.

2. **SSM: open a shell and set the password for DCV**  
   DCV signs in as **`ec2-user`** with a **Linux password** you set yourself. The recommended way (no static secret in Terraform) is **Session Manager**:
   - In **Fleet Manager**, confirm the instance is **Online**.
   - From the **repository root** (works from **WSL** on a Windows checkout under `/mnt/c/...`):

     ```bash
     chmod +x src/ssm-ec2-inital-setup/ssm-connect.sh
     export AWS_PROFILE=personal
     ./src/ssm-ec2-inital-setup/ssm-connect.sh
     ```

   - **Windows (PowerShell):** `.\src\ssm-ec2-inital-setup\ssm-connect.ps1` (set `$env:AWS_PROFILE` as needed).  
   - Inside the session: `sudo passwd ec2-user` and choose a strong password.  
   - **Manual** (from `infrastructure/`):

     ```bash
     aws ssm start-session \
       --target "$(terraform output -raw pybullet_host_instance_id)" \
       --region "$(terraform output -raw aws_region)" \
       --profile personal
     ```

   Optional: `export AWS_REGION=us-east-1` if your environment does not pick up the same region as `provider.tf`.

3. **Open the DCV web client**  
   In a browser, open the DCV URL. Run `terraform output -raw pybullet_host_dcv_url` to print **`https://<PUBLIC_IP>:8443`**, or copy the **`pybullet_host_dcv_url`** value from the apply output in your UI. If it is `null`, the instance has no public address yet (subnets / route tables). You may need to **accept a certificate warning** for a test server.

4. **Sign in to DCV**  
   User **`ec2-user`**, password from step 2. You should see the **GNOME** desktop. PyBullet is installed in a venv: **`/opt/pybullet-venv`** (sourced in **`ec2-user`**’s `~/.bashrc` for new shells). Open a terminal and run: `source /opt/pybullet-venv/bin/activate` if needed, then your Python or PyBullet commands.

5. **Optional: native Amazon DCV client**  
   For some workloads, the native client is preferable: [Download Amazon DCV](https://www.amazondcv.com/) and connect to **`<PUBLIC_IP>:8443`**.

### Optional: quick AWS and CLI check before deploy

```bash
aws configure --profile personal
aws sts get-caller-identity --profile personal
```

**Why `terraform plan` shows “no changes”:** the **saved state** already matches the **current .tf** (including subnet selection). You only see a **replace** the first time you apply after a change, or if you [replace](https://developer.hashicorp.com/terraform/cli/commands/apply#replace) the instance. That does *not* by itself mean SSM is working—confirm the subnet has a path to the internet (or endpoints) and that the **SSM** agent is running.

If SSM stays **Offline**, the instance must reach **AWS Systems Manager** on **HTTPS (443)** (SSM agent to regional endpoints). Common causes: **no internet path** (instance in a **private subnet** with no **NAT gateway** and no **SSM/VPC interface endpoints**), wrong **IAM** (this stack uses **`AmazonSSMManagedInstanceCore`** on the instance profile), or the node is still **booting / running user data** (wait, then check again). The module **prefers a public subnet** (`map-public-ip-on-launch`) when you do not set **`ec2_subnet_id`** in `local.tf`, so the default is suitable for a typical default VPC. In a **private-only** VPC, set **`ec2_subnet_id`** to a subnet that has **NAT** (or add [SSM endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)) and see [SSM agent troubleshooting](https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting-ssm-agent.html).
