# modules/shared/logging-locals.tf
#
# REUSABLE LOGGING PATTERN — reference file for all database/service modules.
#
# This file documents the standard CloudWatch Logs pattern adopted by the
# platform. It is NOT a Terraform module itself (not called via `source`),
# but a COPY-PASTE REFERENCE that each module adapts to its own locals.tf.
#
# ═══════════════════════════════════════════════════════════════════════════════
# PATTERN: CloudWatch Log Group retention guard-rail
# ═══════════════════════════════════════════════════════════════════════════════
#
# Every module that creates CloudWatch Log Groups MUST implement this logic
# in its locals.tf:
#
#   default_log_retention_days = contains(["prod", "dr"], var.ambiente) ? 365 : (var.ambiente == "preprod" ? 90 : 30)
#   log_retention_days         = coalesce(var.cloudwatch_log_retention_days, local.default_log_retention_days)
#
# Environment floors:
#   dev/qa   : 30 days (FinOps — low-cost short retention)
#   preprod  : 90 days (integration debugging window)
#   prod/dr  : 365 days (CIS logging / audit compliance)
#
# A son repo may set a LONGER retention but never below the environment floor
# (enforced by coalesce + the floor being the default).
#
# ═══════════════════════════════════════════════════════════════════════════════
# PATTERN: CloudWatch Logs KMS encryption resolution
# ═══════════════════════════════════════════════════════════════════════════════
#
# Every module MUST encrypt its CloudWatch Log Groups with the account's
# CWLogs CMK. Resolution order:
#
#   1. Explicit ARN (var.cloudwatch_logs_kms_key_arn != "")  → use as-is
#   2. Alias discovery (data.aws_kms_alias.cwlogs)          → resolve target_key_arn
#
# locals.tf:
#   cloudwatch_logs_kms_key_arn = var.cloudwatch_logs_kms_key_arn != "" ? var.cloudwatch_logs_kms_key_arn : data.aws_kms_alias.cwlogs[0].target_key_arn
#
# data.tf:
#   data "aws_kms_alias" "cwlogs" {
#     count = var.cloudwatch_logs_kms_key_arn == "" ? 1 : 0
#     name  = var.cloudwatch_logs_kms_key_alias
#   }
#
# variables.tf:
#   variable "cloudwatch_logs_kms_key_alias" {
#     description = "Alias of the account's pre-existing CloudWatch Logs CMK."
#     type        = string
#     default     = "alias/CWLogs"
#   }
#   variable "cloudwatch_logs_kms_key_arn" {
#     description = "Explicit CloudWatch Logs KMS key ARN override. Empty => discover by alias."
#     type        = string
#     default     = ""
#   }
#   variable "cloudwatch_log_retention_days" {
#     description = "Retention (days) for managed CloudWatch log groups. null = auto by environment."
#     type        = number
#     default     = null
#   }
#
# ═══════════════════════════════════════════════════════════════════════════════
# PATTERN: Log Group naming by AWS service
# ═══════════════════════════════════════════════════════════════════════════════
#
# Each service has a fixed log group path prefix mandated by AWS:
#
#   Aurora PostgreSQL : /aws/rds/cluster/{cluster_name}/postgresql
#   ElastiCache       : /aws/elasticache/{cache_name}/slow-log
#                       /aws/elasticache/{cache_name}/engine-log
#   Lambda            : /aws/lambda/{function_name}
#   API Gateway       : /aws/apigateway/{api_name}/{stage}
#
# IMPORTANT: Pre-create log groups BEFORE enabling log export on the service.
# If the service auto-creates the log group, it uses NEVER-EXPIRE retention
# and AWS-owned encryption (violates CIS + FinOps requirements).
#
# ═══════════════════════════════════════════════════════════════════════════════
# PATTERN: Log Group resource block template
# ═══════════════════════════════════════════════════════════════════════════════
#
#   resource "aws_cloudwatch_log_group" "<logical_name>" {
#     name              = local.<log_group_name_local>
#     retention_in_days = local.log_retention_days
#     kms_key_id        = local.cloudwatch_logs_kms_key_arn
#     tags              = merge(local.tags, { Name = local.<log_group_name_local> })
#   }
#
# ═══════════════════════════════════════════════════════════════════════════════
# ADOPTION CHECKLIST (for new modules)
# ═══════════════════════════════════════════════════════════════════════════════
#
# [ ] Add cloudwatch_logs_kms_key_alias variable (default "alias/CWLogs")
# [ ] Add cloudwatch_logs_kms_key_arn variable (default "")
# [ ] Add cloudwatch_log_retention_days variable (default null, with validation)
# [ ] Add data "aws_kms_alias" "cwlogs" conditional lookup in data.tf
# [ ] Add default_log_retention_days, log_retention_days, cloudwatch_logs_kms_key_arn in locals.tf
# [ ] Add log group name locals following AWS path convention
# [ ] Create logs.tf with aws_cloudwatch_log_group resources
# [ ] Wire log groups into the service resource (depends_on or explicit ref)
# [ ] Add log_group_names output
# [ ] Pass cloudwatch_logs_kms_key_alias and _arn from product module
#
# Modules implementing this pattern:
#   - modules/database/aurora-postgresql (logs.tf) — 1 log group: postgresql
#   - modules/database/elasticache-serverless (logs.tf) — 2 log groups: slow-log, engine-log
