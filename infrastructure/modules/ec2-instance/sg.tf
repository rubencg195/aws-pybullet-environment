resource "aws_security_group" "this" {
  name_prefix = "${var.project_name}-ec2-"
  description = "PyBullet / GPU: SSH, DCV (8443), egress, SSM."
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.sg_ingress_cidrs
  }

  ingress {
    description = "NICE/Amazon DCV (HTTPS, web and native client)"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.sg_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    { Name = "${var.project_name}-ec2-sg" },
    var.tags
  )
}
