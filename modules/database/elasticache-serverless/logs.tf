# modules/database/elasticache-serverless/logs.tf
#
# Managed CloudWatch Log Groups for ElastiCache log delivery.
#
# WHY: Pre-creating log groups ensures they have the correct retention and CMK
# encryption from day one. When AWS enables log delivery for serverless caches
# (currently NOT supported — only replication groups), these log groups will be
# picked up automatically without changes.
#
# AWS LIMITATION (as of 2026-08):
#   "Log delivery is not supported for serverless caches."
#   — https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Log_Delivery.html
#
# The log_delivery_configuration block is only available on
# aws_elasticache_replication_group, NOT aws_elasticache_serverless_cache.
# These log groups are provisioned PROACTIVELY so that:
#   1. The naming convention and encryption are established NOW.
#   2. If the module is later adapted for replication groups, logs are ready.
#   3. When AWS adds serverless log delivery, a one-line change enables it.
#
# Two log types are defined for ElastiCache (replication groups):
#   - slow-log  : queries exceeding the slowlog-log-slower-than threshold
#   - engine-log: internal engine events (connections, evictions, failovers)
#
# Naming follows the AWS convention:
#   /aws/elasticache/{cache-name}/slow-log
#   /aws/elasticache/{cache-name}/engine-log

resource "aws_cloudwatch_log_group" "slow_log" {
  name              = local.slow_log_group_name
  retention_in_days = local.log_retention_days
  kms_key_id        = local.cloudwatch_logs_kms_key_arn

  tags = merge(local.tags, { Name = local.slow_log_group_name })
}

resource "aws_cloudwatch_log_group" "engine_log" {
  name              = local.engine_log_group_name
  retention_in_days = local.log_retention_days
  kms_key_id        = local.cloudwatch_logs_kms_key_arn

  tags = merge(local.tags, { Name = local.engine_log_group_name })
}
