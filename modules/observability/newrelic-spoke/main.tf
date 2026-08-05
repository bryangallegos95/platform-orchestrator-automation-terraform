# modules/observability/newrelic-spoke/main.tf
#
# New Relic spoke — subscription filters that forward CloudWatch Logs
# to a centralized hub destination (Kinesis Firehose → New Relic).
#
# This module does NOT create the hub (Kinesis/Firehose/Lambda).
# It only creates:
#   1. An IAM role that CloudWatch Logs assumes to put records to the destination
#   2. One subscription filter per log group

locals {
  name_prefix = "nr-${var.ambiente}-${var.workload}-${var.funcionalidad}"

  # Build a map for for_each: key = sanitized LG name, value = original name
  log_group_map = { for lg in var.log_group_names : replace(lg, "/", "-") => lg }
}

# ═══════════════════════════════════════════════════════════════════════════════
# IAM ROLE — CloudWatch Logs assumes this to write to the destination
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "cw_to_destination" {
  name = "rol-aw-${var.aws_region == "us-east-2" ? "ue2" : "ue1"}-${var.workload}-${var.funcionalidad}-nr-spoke-${var.ambiente}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCWLogsAssume"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      },
    ]
  })

  tags = {
    Name    = "rol-aw-nr-spoke-${var.ambiente}"
    Module  = "newrelic-spoke"
    Workload = var.workload
  }
}

resource "aws_iam_role_policy" "cw_to_destination" {
  name = "nr-spoke-put-logs"
  role = aws_iam_role.cw_to_destination.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPutToDestination"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "firehose:PutRecord",
          "firehose:PutRecordBatch",
          "kinesis:PutRecord",
          "kinesis:PutRecords",
        ]
        Resource = ["*"]
      },
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUBSCRIPTION FILTERS — one per log group
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_cloudwatch_log_subscription_filter" "to_hub" {
  for_each = local.log_group_map

  name            = "nr-${var.ambiente}-${each.key}"
  log_group_name  = each.value
  destination_arn = var.hub_destination_arn
  filter_pattern  = var.filter_pattern
  role_arn        = aws_iam_role.cw_to_destination.arn
}
