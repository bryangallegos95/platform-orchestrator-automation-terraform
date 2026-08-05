# modules/product/newrelic.tf
#
# New Relic spoke building block — conditional deployment.
# Creates CloudWatch Logs subscription filters that forward all workload
# log groups to a centralized hub destination (Kinesis Firehose → New Relic).
#
# The spoke consumes the consolidated all_log_group_names list from the
# compositor outputs. If no log groups exist (all blocks disabled), the
# module receives an empty list and creates zero subscription filters.

locals {
  # Internal reference: consolidated log group names from all enabled blocks.
  # Mirrors the logic in outputs.tf but as a local for internal consumption.
  all_log_group_names = concat(
    var.aurora_enabled ? [module.aurora[0].cloudwatch_log_group_name] : [],
    # ElastiCache Serverless does not produce CloudWatch Log Groups
    # SQS does not produce CloudWatch Log Groups
  )
}

module "newrelic_spoke" {
  count  = var.newrelic_enabled ? 1 : 0
  source = "../observability/newrelic-spoke"

  # ── Identity (common) ───────────────────────────────────────────────────────
  aws_region     = var.aws_region
  service        = var.service
  workload       = var.workload
  funcionalidad  = var.funcionalidad
  ambiente       = var.ambiente
  aws_account_id = var.aws_account_id

  # ── Spoke configuration ─────────────────────────────────────────────────────
  log_group_names     = local.all_log_group_names
  hub_destination_arn = var.newrelic_hub_destination_arn
}
