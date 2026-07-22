# modules/database/aurora-postgresql/outputs.tf
#
# Exposes all identifiers that son-repo stacks or other modules may need.
# Pattern: one output per resource, plus discovery context for traceability.

# ── Cluster ───────────────────────────────────────────────────────────────────
output "cluster_id" {
  description = "Identifier of the Aurora cluster."
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the Aurora cluster."
  value       = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "Immutable cluster resource ID — needed to build rds-db:connect ARNs for IAM database authentication."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "writer_endpoint" {
  description = "Writer endpoint (read/write). Point application write traffic here."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint (load-balanced across readers). Point read-only traffic here."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Port the cluster listens on (platform standard: 15432). Consumers must target this port."
  value       = aws_rds_cluster.this.port
}

output "engine_version" {
  description = "Actual engine version of the cluster."
  value       = aws_rds_cluster.this.engine_version_actual
}

output "master_username" {
  description = "Admin service user of the cluster (credential lives in BeyondTrust Secrets Safe)."
  value       = aws_rds_cluster.this.master_username
}

# ── Instances ─────────────────────────────────────────────────────────────────
output "instance_identifiers" {
  description = "Map of instance key => instance identifier."
  value       = { for k, v in aws_rds_cluster_instance.this : k => v.identifier }
}

output "instance_endpoints" {
  description = "Map of instance key => individual instance endpoint (prefer writer/reader endpoints for applications)."
  value       = { for k, v in aws_rds_cluster_instance.this : k => v.endpoint }
}

# ── IAM database authentication ───────────────────────────────────────────────
output "iam_auth_resource_arn_prefix" {
  description = "Resource ARN prefix for rds-db:connect IAM policies. Append '/{db_username}' to grant a workload role access to a specific database user."
  value       = "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${aws_rds_cluster.this.cluster_resource_id}"
}

# ── Security Group ────────────────────────────────────────────────────────────
output "security_group_id" {
  description = "ID of the module-managed Security Group. Reference it from consumer SGs, or pass consumer SG IDs via allowed_security_group_ids."
  value       = aws_security_group.this.id
}

# ── KMS ───────────────────────────────────────────────────────────────────────
output "kms_key_arn" {
  description = "ARN of the pre-existing RDS CMK the cluster storage is encrypted with (discovered by alias or passed in)."
  value       = local.kms_key_arn
}

# ── Observability / logs ──────────────────────────────────────────────────────
output "cloudwatch_log_group_name" {
  description = "Name of the managed PostgreSQL CloudWatch log group (retention + CMK-encrypted)."
  value       = aws_cloudwatch_log_group.postgresql.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the managed PostgreSQL CloudWatch log group."
  value       = aws_cloudwatch_log_group.postgresql.arn
}

# ── Storage model ─────────────────────────────────────────────────────────────
output "storage_type" {
  description = "Effective Aurora storage model ('standard' or 'aurora-iopt1')."
  value       = var.storage_type
}

# ── Parameter groups ──────────────────────────────────────────────────────────
output "cluster_parameter_group_name" {
  description = "Name of the cluster parameter group (security baseline + overrides)."
  value       = aws_rds_cluster_parameter_group.this.name
}

output "instance_parameter_group_name" {
  description = "Name of the instance (DB) parameter group."
  value       = aws_db_parameter_group.this.name
}

# ── Global Database ───────────────────────────────────────────────────────────
output "global_cluster_identifier" {
  description = "Identifier of the Global Database (only when enable_global_database=true on prod; pass it to the dr environment)."
  value       = var.enable_global_database && var.ambiente == "prod" ? aws_rds_global_cluster.this[0].global_cluster_identifier : ""
}

# ── Discovery context (traceability) ──────────────────────────────────────────
output "vpc_id" {
  description = "ID of the discovered Spoke VPC the cluster lives in."
  value       = data.aws_vpc.spoke.id
}

output "subnet_group_name" {
  description = "Name of the DB subnet group (spans both BDD-tier subnets)."
  value       = aws_db_subnet_group.this.name
}

output "monitoring_role_arn" {
  description = "ARN of the Enhanced Monitoring role (empty when monitoring is off)."
  value       = local.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : ""
}
