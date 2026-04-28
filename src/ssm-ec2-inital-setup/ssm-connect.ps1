# SSM session to the PyBullet EC2 host (Windows PowerShell).
# After connect:  sudo passwd ec2-user
#
# From repo root:
#   .\src\ssm-ec2-inital-setup\ssm-connect.ps1
#
# Optional:  $env:AWS_PROFILE  $env:AWS_REGION
#

$ErrorActionPreference = "Stop"

$ScriptRoot = $PSScriptRoot
$ProjectRoot = (Resolve-Path (Join-Path $ScriptRoot "..\..")).Path
$Infra = Join-Path $ProjectRoot "infrastructure"
Set-Location $Infra

if (-not $env:AWS_PROFILE) { $env:AWS_PROFILE = "personal" }

$iac = "terraform"
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { $iac = "tofu" }
if (-not (Get-Command $iac -ErrorAction SilentlyContinue)) {
  throw "Install HashiCorp Terraform (terraform) or OpenTofu (tofu); apply the stack in infrastructure/ first."
}

$region = $env:AWS_REGION
if (-not $region) { $region = & $iac output -raw aws_region 2>$null }
if (-not $region) { $region = aws configure get region --profile $env:AWS_PROFILE 2>$null }
if (-not $region) { $region = "us-east-1" }

$id = & $iac output -raw pybullet_host_instance_id
& aws ssm start-session --target $id --region $region --profile $env:AWS_PROFILE
