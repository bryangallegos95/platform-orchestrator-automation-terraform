# modules/product/outputs.tf
#
# Exposes all identifiers that consumer stacks (Helm charts, CI/CD, ArgoCD,
# monitoring) may need. All outputs are conditional — empty/null when the
# corresponding building block is disabled.

# ═══════════════════════════════════════════════════════════════════════════════
# AURORA POSTGRESQL
# ═══════════════════════════════════════════════════════════════════════════════

output "aurora_cluster_id" {
  description = "Aurora cluster identifier."
  value       = var.aurora_enabled ? module.aurora[0].cluster_id : ""
}

output "aurora_cluster_arn" {
  description = "Aurora cluster ARN."
  value       = var.aurora_enabled ? module.aurora[0].cluster_arn : ""
}

output "aurora_cluster_resource_id" {
  description = "Aurora cluster resource ID (for rds-db:connect ARNs)."
  value       = var.aurora_enabled ? module.aurora[0].cluster_resource_id : ""
}

output "aurora_writer_endpoint" {
  description = "Aurora writer endpoint (read/write traffic)."
  value       = var.aurora_enabled ? module.aurora[0].writer_endpoint : ""
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint (load-balanced read-only traffic)."
  value       = var.aurora_enabled ? module.aurora[0].reader_endpoint : ""
}

output "aurora_port" {
  description = "Aurora port (platform standard: 15432)."
  value       = var.aurora_enabled ? module.aurora[0].port : null
}

output "aurora_security_group_id" {
  description = "Aurora module-managed Security Group ID."
  value       = var.aurora_enabled ? module.aurora[0].security_group_id : ""
}

output "aurora_iam_auth_resource_arn_prefix" {
  description = "Resource ARN prefix for rds-db:connect IAM policies. Append '/{db_username}'."
  value       = var.aurora_enabled ? module.aurora[0].iam_auth_resource_arn_prefix : ""
}

output "aurora_kms_key_arn" {
  description = "ARN of the KMS CMK used for Aurora storage encryption."
  value       = var.aurora_enabled ? module.aurora[0].kms_key_arn : ""
}

output "aurora_vpc_id" {
  description = "VPC ID where Aurora is deployed."
  value       = var.aurora_enabled ? module.aurora[0].vpc_id : ""
}

output "aurora_engine_version" {
  description = "Actual engine version of the Aurora cluster."
  value       = var.aurora_enabled ? module.aurora[0].engine_version : ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SQS
# ═══════════════════════════════════════════════════════════════════════════════

output "sqs_queue_arns" {
  description = "Map of queue key to ARN for all main queues."
  value       = var.sqs_enabled ? module.sqs[0].queue_arns : {}
}

output "sqs_queue_urls" {
  description = "Map of queue key to URL for all main queues."
  value       = var.sqs_enabled ? module.sqs[0].queue_urls : {}
}

output "sqs_queue_names" {
  description = "Map of queue key to name for all main queues."
  value       = var.sqs_enabled ? module.sqs[0].queue_names : {}
}

output "sqs_dlq_arns" {
  description = "Map of queue key to ARN for all DLQs."
  value       = var.sqs_enabled ? module.sqs[0].dlq_arns : {}
}

output "sqs_dlq_urls" {
  description = "Map of queue key to URL for all DLQs."
  value       = var.sqs_enabled ? module.sqs[0].dlq_urls : {}
}

output "sqs_kms_key_arn" {
  description = "ARN of the KMS CMK used for SQS encryption."
  value       = var.sqs_enabled ? module.sqs[0].kms_key_arn : ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# ELASTICACHE SERVERLESS (REDIS / VALKEY)
# ═══════════════════════════════════════════════════════════════════════════════

output "redis_cache_name" {
  description = "ElastiCache Serverless cache name."
  value       = var.redis_enabled ? module.redis[0].cache_name : ""
}

output "redis_cache_arn" {
  description = "ElastiCache Serverless cache ARN."
  value       = var.redis_enabled ? module.redis[0].cache_arn : ""
}

output "redis_endpoint" {
  description = "ElastiCache primary endpoint (address + port)."
  value       = var.redis_enabled ? module.redis[0].endpoint : null
}

output "redis_reader_endpoint" {
  description = "ElastiCache reader endpoint (address + port)."
  value       = var.redis_enabled ? module.redis[0].reader_endpoint : null
}

output "redis_security_group_id" {
  description = "ElastiCache module-managed Security Group ID."
  value       = var.redis_enabled ? module.redis[0].security_group_id : ""
}

output "redis_kms_key_arn" {
  description = "ARN of the KMS CMK used for ElastiCache encryption."
  value       = var.redis_enabled ? module.redis[0].kms_key_arn : ""
}

output "redis_vpc_id" {
  description = "VPC ID where ElastiCache is deployed."
  value       = var.redis_enabled ? module.redis[0].vpc_id : ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# IRSA
# ═══════════════════════════════════════════════════════════════════════════════

output "irsa_role_arns" {
  description = "Map of IRSA role key to IAM role ARN."
  value       = var.irsa_enabled ? module.irsa[0].role_arns : {}
}

output "irsa_role_names" {
  description = "Map of IRSA role key to IAM role name."
  value       = var.irsa_enabled ? module.irsa[0].role_names : {}
}

output "irsa_sa_annotations" {
  description = "Map of IRSA role key to ServiceAccount annotation value (role ARN for eks.amazonaws.com/role-arn)."
  value       = var.irsa_enabled ? module.irsa[0].sa_annotations : {}
}

output "irsa_oidc_provider_arn" {
  description = "ARN of the OIDC provider used for IRSA trust policies."
  value       = var.irsa_enabled ? module.irsa[0].oidc_provider_arn : ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SQS ALARMS
# ═══════════════════════════════════════════════════════════════════════════════

output "sqs_dlq_alarm_arns" {
  description = "Map of queue key to DLQ depth alarm ARN."
  value       = var.sqs_enabled ? module.sqs[0].dlq_alarm_arns : {}
}

output "sqs_age_alarm_arns" {
  description = "Map of queue key to message age alarm ARN."
  value       = var.sqs_enabled ? module.sqs[0].age_alarm_arns : {}
}

# ═══════════════════════════════════════════════════════════════════════════════
# OBSERVABILITY — CONSOLIDATED LOG GROUP NAMES
# ═══════════════════════════════════════════════════════════════════════════════
# Prerequisite for New Relic spoke: downstream consumers need a single list
# of all CloudWatch Log Group names produced by this workload to set up
# subscription filters.

output "all_log_group_names" {
  description = "Consolidated list of all CloudWatch Log Group names from enabled building blocks. Used by the New Relic spoke to subscribe to all workload logs."
  value       = local.all_log_group_names
}

# ═══════════════════════════════════════════════════════════════════════════════
# NEW RELIC SPOKE
# ═══════════════════════════════════════════════════════════════════════════════

output "newrelic_subscription_filter_arns" {
  description = "Map of sanitized log group key to subscription filter ARN."
  value       = var.newrelic_enabled ? module.newrelic_spoke[0].subscription_filter_arns : {}
}

output "newrelic_iam_role_arn" {
  description = "ARN of the IAM role assumed by CloudWatch Logs for the New Relic spoke."
  value       = var.newrelic_enabled ? module.newrelic_spoke[0].iam_role_arn : ""
}
