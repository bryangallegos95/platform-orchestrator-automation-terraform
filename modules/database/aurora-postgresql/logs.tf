# modules/database/aurora-postgresql/logs.tf
#
# Managed CloudWatch Log Group for the PostgreSQL log export.
#
# WHY: if RDS auto-creates the export log group it uses NEVER-EXPIRE retention
# and the account default (AWS-owned) encryption. Managing it here gives us:
#   - a defined, environment-differentiated retention (FinOps + CIS logging)
#   - encryption with the account's CloudWatch Logs CMK (alias/CWLogs)
#
# The name matches the fixed path RDS writes to
# (/aws/rds/cluster/<cluster-id>/postgresql), and the cluster depends_on this
# group (see main.tf) so it exists BEFORE RDS starts exporting — RDS then
# reuses it instead of creating an unmanaged one.

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = local.postgresql_log_group_name
  retention_in_days = local.log_retention_days
  kms_key_id        = local.cloudwatch_logs_kms_key_arn

  tags = merge(local.tags, { Name = local.postgresql_log_group_name })
}
