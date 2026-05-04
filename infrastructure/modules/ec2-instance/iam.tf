resource "aws_iam_role" "this" {
  name_prefix        = "${var.project_name}-ec2-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags = merge(
    { Name = "${var.project_name}-ec2" },
    var.tags
  )
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.this.name
  tags = merge(
    { Name = "${var.project_name}-ec2" },
    var.tags
  )
}
