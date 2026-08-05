# modules/database/elasticache-serverless/main.tf
#
# ElastiCache Serverless cache in an existing Spoke VPC.
# One module call = one serverless cache.
#
# What this module creates:
#   1. ElastiCache Serverless cache (Valkey or Redis OSS)
#   2. Dedicated Security Group (no inbound by default)
#   3. Additive KMS grants for consumer workload roles
#
# What this module does NOT create:
#   - VPC / subnets / routing  -> modules/networking/vpc
#   - KMS keys                 -> account baseline (discovered by alias)
#   - IAM roles for consumers  -> modules/identity/irsa-role
#
# Hardening baked in (not configurable off):
#   - TLS in-transit: FORCED by ElastiCache Serverless (cannot disable)
#   - At-rest encryption: CMK (account's existing ElastiCache CMK)
#   - VPC-only: private subnets, no public access
#   - IAM authentication: native to Serverless
#   - Security Group: deny-all inbound by default
#   - Dual port SG rules (6379 + 6380) for all consumers


# ── ElastiCache Serverless Cache ──────────────────────────────────────────────
resource "aws_elasticache_serverless_cache" "this" {
  name   = local.cache_name
  engine = var.engine

  major_engine_version = var.major_engine_version

  # ── Encryption — LOCKED ──────────────────────────────────────────────────
  # At-rest: CMK (account baseline key discovered by alias)
  # In-transit: FORCED by Serverless (no flag needed — always TLS)
  kms_key_id = local.kms_key_arn

  # ── Network — VPC-only (private subnets) ─────────────────────────────────
  # ElastiCache Serverless creates VPC endpoints in these subnets.
  subnet_ids         = [data.aws_subnet.cache_a.id, data.aws_subnet.cache_b.id]
  security_group_ids = [aws_security_group.this.id]

  # ── Usage Limits (FinOps guard-rails) ────────────────────────────────────
  cache_usage_limits {
    ecpu_per_second {
      maximum = local.effective_max_ecpu
    }
    data_storage {
      maximum = local.effective_max_storage
      unit    = "GB"
    }
  }

  # ── Snapshots ────────────────────────────────────────────────────────────
  snapshot_retention_limit = local.snapshot_retention_days
  daily_snapshot_time      = var.daily_snapshot_time

  # ── User Group (IAM auth) ────────────────────────────────────────────────
  user_group_id = var.user_group_id != "" ? var.user_group_id : null

  tags = merge(local.tags, { Name = local.cache_name })

  depends_on = [
    terraform_data.guards,
    aws_cloudwatch_log_group.slow_log,
    aws_cloudwatch_log_group.engine_log,
  ]

  lifecycle {
    # FinOps: snapshot retention floor enforcement
    precondition {
      condition     = local.snapshot_retention_days >= local.snapshot_retention_floor
      error_message = "snapshot_retention_days cannot be below the ${var.ambiente} floor of ${local.snapshot_retention_floor} days."
    }
  }
}
