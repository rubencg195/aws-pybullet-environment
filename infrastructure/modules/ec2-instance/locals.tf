locals {
  # Explicit subnet wins. Otherwise pick a public subnet (IGW + default public IP) so
  # the SSM agent can register. If the VPC has no public subnets, fall back to any
  # subnet (e.g. private + NAT) — in that case ensure routing/NAT or add SSM endpoints.
  subnet_id = coalesce(
    var.subnet_id,
    length(data.aws_subnets.public.ids) > 0 ? sort(data.aws_subnets.public.ids)[0] : null,
    sort(data.aws_subnets.this.ids)[0]
  )
}
