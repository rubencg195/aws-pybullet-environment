# -----------------------------------------------------------------------------
# Artifacts bucket for deep PyBullet tests (GIF uploads from run_sim_and_upload.py).
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "pybullet_sim" {
  bucket = local.pybullet_sim_bucket_name

  # Sim GIFs are ephemeral (lifecycle on sim-runs/); allow tofu destroy without manual emptying.
  force_destroy = true

  tags = {
    Name    = "${local.project_name}-pybullet-sim-artifacts"
    Purpose = "pybullet-headless-sim-recordings"
  }
}

resource "aws_s3_bucket_public_access_block" "pybullet_sim" {
  bucket = aws_s3_bucket.pybullet_sim.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pybullet_sim" {
  bucket = aws_s3_bucket.pybullet_sim.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "pybullet_sim" {
  bucket = aws_s3_bucket.pybullet_sim.id

  rule {
    id     = "expire-sim-runs"
    status = "Enabled"

    filter {
      prefix = "sim-runs/"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_iam_role_policy" "pybullet_host_s3_sim_upload" {
  name = "${local.project_name}-pybullet-sim-s3-put"
  role = module.pybullet_host.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PyBulletSimUpload"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = "${aws_s3_bucket.pybullet_sim.arn}/sim-runs/*"
      }
    ]
  })
}
