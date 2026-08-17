# modules/database/dynamodb/outputs.tf
#
# Exposes every identifier a son-repo stack, the compositor or the application
# layer may need. Pattern: one output per table, plus the aggregates used to
# build IAM policies and the values the writer needs to honour the data contract.

# ── logs ──────────────────────────────────────────────────────────────────────
output "logs_table_name" {
  description = "Name of the primary audit log table."
  value       = aws_dynamodb_table.logs.name
}

output "logs_table_arn" {
  description = "ARN of the primary audit log table."
  value       = aws_dynamodb_table.logs.arn
}

output "logs_stream_arn" {
  description = "Stream ARN of the logs table — feeds the S3 analytics archive (Firehose) and, if ever reactivated, search indexing."
  value       = aws_dynamodb_table.logs.stream_arn
}

# ── log-payloads ──────────────────────────────────────────────────────────────
output "payloads_table_name" {
  description = "Name of the hot payload cache table (canonical copy lives in S3)."
  value       = aws_dynamodb_table.payloads.name
}

output "payloads_table_arn" {
  description = "ARN of the hot payload cache table."
  value       = aws_dynamodb_table.payloads.arn
}

# ── applications ──────────────────────────────────────────────────────────────
output "applications_table_name" {
  description = "Name of the producer application catalog table."
  value       = aws_dynamodb_table.applications.name
}

output "applications_table_arn" {
  description = "ARN of the producer application catalog table."
  value       = aws_dynamodb_table.applications.arn
}

# ── services ──────────────────────────────────────────────────────────────────
output "services_table_name" {
  description = "Name of the service catalog table."
  value       = aws_dynamodb_table.services.name
}

output "services_table_arn" {
  description = "ARN of the service catalog table."
  value       = aws_dynamodb_table.services.arn
}

output "catalog_stream_arns" {
  description = "Stream ARNs of the catalog tables (applications, services) — they invalidate the in-memory cache of the Lambdas."
  value = [
    aws_dynamodb_table.applications.stream_arn,
    aws_dynamodb_table.services.stream_arn,
  ]
}

# ── wait-logs ─────────────────────────────────────────────────────────────────
output "wait_logs_table_name" {
  description = "Name of the deferred (wait) log table."
  value       = aws_dynamodb_table.wait_logs.name
}

output "wait_logs_table_arn" {
  description = "ARN of the deferred (wait) log table."
  value       = aws_dynamodb_table.wait_logs.arn
}

# ── Aggregates for IAM policies ───────────────────────────────────────────────
output "table_names" {
  description = "Map of logical table key => table name."
  value = {
    logs         = aws_dynamodb_table.logs.name
    payloads     = aws_dynamodb_table.payloads.name
    applications = aws_dynamodb_table.applications.name
    services     = aws_dynamodb_table.services.name
    wait_logs    = aws_dynamodb_table.wait_logs.name
  }
}

output "table_arns" {
  description = "ARNs of the five tables, for the Resource block of the Lambda IAM policies."
  value = [
    aws_dynamodb_table.logs.arn,
    aws_dynamodb_table.payloads.arn,
    aws_dynamodb_table.applications.arn,
    aws_dynamodb_table.services.arn,
    aws_dynamodb_table.wait_logs.arn,
  ]
}

# The logs table is deliberately ABSENT here: it has no secondary indexes, and
# granting an empty pattern in an IAM policy only confuses whoever audits it
# (CL-LLD-DAT-01 §10.1). log-payloads has none either.
output "index_arns" {
  description = "Index ARN patterns of the tables that DO have secondary indexes (applications, services, wait-logs). The logs table has no GSI and is intentionally not listed."
  value = [
    "${aws_dynamodb_table.applications.arn}/index/*",
    "${aws_dynamodb_table.services.arn}/index/*",
    "${aws_dynamodb_table.wait_logs.arn}/index/*",
  ]
}

output "iam_resource_arns" {
  description = "table_arns + index_arns — ready to drop into the Resource block of a Lambda IAM policy."
  value = concat(
    [
      aws_dynamodb_table.logs.arn,
      aws_dynamodb_table.payloads.arn,
      aws_dynamodb_table.applications.arn,
      aws_dynamodb_table.services.arn,
      aws_dynamodb_table.wait_logs.arn,
    ],
    [
      "${aws_dynamodb_table.applications.arn}/index/*",
      "${aws_dynamodb_table.services.arn}/index/*",
      "${aws_dynamodb_table.wait_logs.arn}/index/*",
    ]
  )
}

# ── Data contract for the application layer ───────────────────────────────────
output "ttl_attribute_name" {
  description = "Name of the TTL attribute the writer must populate on logs, log-payloads and wait-logs. DynamoDB only NAMES this attribute — nothing expires unless the writer sets it."
  value       = var.ttl_attribute_name
}

output "ttl_retention_days" {
  description = "Effective hot retention window in days (after applying the per-environment floor). The ingest Lambda computes exp = now + this window. DECISIÓN DE NEGOCIO PENDIENTE: 30 vs 90 — CL-LLD-DAT-01 §12.2 #4."
  value       = local.ttl_retention_days
}

# ── Configuration context (traceability) ──────────────────────────────────────
output "kms_key_arn" {
  description = "ARN of the pre-existing DynamoDB CMK the tables are encrypted with (discovered by alias or passed in)."
  value       = local.kms_key_arn
}

output "billing_mode" {
  description = "Effective billing mode of the high-volume tables (logs, log-payloads)."
  value       = var.billing_mode
}

output "autoscaling_enabled" {
  description = "Whether Application Auto Scaling is attached to the logs table (true only in PROVISIONED mode)."
  value       = local.logs_autoscaling
}

output "capacity_ceilings" {
  description = "Effective per-environment Auto Scaling ceilings after clamping the requested maxima."
  value = {
    read_ceiling  = local.read_capacity_ceiling
    write_ceiling = local.write_capacity_ceiling
    read_max      = local.read_capacity_max
    write_max     = local.write_capacity_max
  }
}
