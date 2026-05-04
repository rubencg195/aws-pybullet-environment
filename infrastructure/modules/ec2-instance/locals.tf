locals {
  subnet_id = coalesce(
    var.subnet_id,
    length(data.aws_subnets.filtered.ids) > 0 ? sort(data.aws_subnets.filtered.ids)[0] : null,
  )
}
