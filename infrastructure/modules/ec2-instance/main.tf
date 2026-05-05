resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = local.subnet_id

  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  user_data              = var.user_data != null ? var.user_data : ""

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true

    tags = merge(
      {
        Name    = "${var.project_name}-pybullet-root"
        Service = "pybullet-host"
      },
      var.tags
    )
  }

  metadata_options {
    http_tokens = "required"
  }

  lifecycle {
    precondition {
      condition     = local.subnet_id != null
      error_message = "No subnet resolved: set local.ec2_subnet_id or add a VPC subnet whose Name matches *public* (see data.aws_subnets.filtered in the ec2-instance module)."
    }
  }

  tags = merge(
    {
      Name    = "${var.project_name}-pybullet"
      Service = "pybullet-host"
    },
    var.tags
  )
}
