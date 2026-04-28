module "pybullet_host" {
  source = "./modules/ec2-instance"

  project_name  = local.project_name
  vpc_id        = data.aws_vpc.this.id
  instance_type = local.ec2_instance_type
  key_name         = local.ec2_key_name
  subnet_id        = local.ec2_subnet_id
  sg_ingress_cidrs = local.sg_ingress_cidrs
}
