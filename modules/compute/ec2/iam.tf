# modules/compute/ec2/iam.tf
#
# Instance role + profile.
#
# AmazonSSMManagedInstanceCore is ALWAYS attached — Session Manager is the
# bank-standard access path (no SSH keys, no inbound ports, full audit trail
# in CloudTrail/S3). Extra permissions are opt-in via
# var.additional_iam_policy_arns.
#
# The trust policy is scoped with aws:SourceAccount to prevent the
# confused-deputy problem (an instance in another account assuming this role).

resource "aws_iam_role" "this" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = local.tags
}

# SSM Session Manager — always on.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Optional extra managed policies (e.g. CloudWatchAgentServerPolicy).
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_iam_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = local.instance_profile_name
  role = aws_iam_role.this.name

  tags = local.tags
}
