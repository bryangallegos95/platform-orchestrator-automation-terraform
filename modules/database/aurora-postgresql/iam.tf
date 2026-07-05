# modules/database/aurora-postgresql/iam.tf
#
# Enhanced Monitoring role — created only when monitoring_interval > 0
# (auto: prod-like envs). RDS assumes it to publish OS-level metrics.
#
# The trust policy is scoped with aws:SourceAccount to prevent the
# confused-deputy problem (an RDS resource in another account assuming
# this role).

resource "aws_iam_role" "monitoring" {
  count = local.monitoring_interval > 0 ? 1 : 0

  name = local.monitoring_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
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

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = local.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
