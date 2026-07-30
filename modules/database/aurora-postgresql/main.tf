# modules/database/aurora-postgresql/main.tf
#
# Aurora PostgreSQL cluster in an existing Spoke VPC (Hub-and-Spoke topology).
# One module call = one cluster. Topology by environment:
#   dev/qa/preprod : single-AZ — 1 writer instance (cost-optimised)
#   prod           : multi-AZ  — writer (AZ-a) + reader (AZ-b), auto-failover
#   dr             : mirror in us-east-2; opt-in Aurora Global Database
#                    replication via enable_global_database (prod) +
#                    global_cluster_identifier (dr)
#
# Compute model (orthogonal to the topology above):
#   provisioned (default) : fixed instance_class (e.g. db.r6g.large)
#   serverless v2         : var.serverless = true — instances become
#                           db.serverless and scale between min/max ACUs;
#                           min_acu = 0 adds auto-pause (dev/qa only,
#                           blocked by precondition in prod-like envs)
#
# What this module creates:
#   1. DB subnet group over the discovered BDD-tier subnets (both AZs)
#   2. Aurora PostgreSQL cluster encrypted with the account's EXISTING RDS CMK
#   3. Cluster instances (map-driven — son repos add/resize instances)
#   4. Cluster + instance parameter groups (TLS forced, audit logging)
#   5. Dedicated Security Group (no inbound by default — opt-in 15432 rules)
#   6. Enhanced Monitoring IAM role (prod-like envs)
#   7. Additive KMS grants for consumer workload roles (lambda/ecs/etc.)
#
# What this module does NOT create (lives elsewhere):
#   - VPC / subnets / routing        → modules/networking/vpc
#   - KMS keys                       → account baseline (discovered by alias)
#   - Admin credential value         → BeyondTrust Secrets Safe (injected by
#                                      ci.yml secret_titles → TF_VAR_master_password)
#
# Hardening baked in (not configurable off):
#   - Storage encryption with CMK (always on)
#   - IAM database authentication enabled
#   - TLS forced (rds.force_ssl=1 in the cluster parameter group)
#   - Not publicly accessible; BDD-tier private subnets only
#   - PostgreSQL logs exported to CloudWatch
#   - Deletion protection + final snapshot auto-enabled in preprod/prod/dr

# ── Subnet group ──────────────────────────────────────────────────────────────
# Always spans both BDD subnets: a single-AZ cluster can later scale to
# multi-AZ by adding an instance — no subnet-group replacement needed.
resource "aws_db_subnet_group" "this" {
  name        = local.subnet_group_name
  description = "BDD-tier subnets for ${local.cluster_name}. Managed by Terraform (database/aurora-postgresql module)."
  subnet_ids  = [data.aws_subnet.bdd_a.id, data.aws_subnet.bdd_b.id]

  tags = merge(local.tags, { Name = local.subnet_group_name })
}

# ── Aurora cluster ────────────────────────────────────────────────────────────
resource "aws_rds_cluster" "this" {
  cluster_identifier = local.cluster_name
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  port               = local.db_port # 🔒 LOCKED — 15432 (platform security standard)

  # Global-secondary clusters (dr) inherit credentials/database from the
  # primary — defining them is an API error.
  database_name             = local.is_global_secondary ? null : (var.database_name != "" ? var.database_name : null)
  master_username           = local.is_global_secondary ? null : var.master_username
  master_password           = local.is_global_secondary ? null : var.master_password
  global_cluster_identifier = local.is_global_secondary ? local.effective_global_cluster_identifier : null

  db_subnet_group_name            = aws_db_subnet_group.this.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  vpc_security_group_ids = concat(
    [aws_security_group.this.id],
    var.additional_security_group_ids
  )

  # ── Serverless v2 scaling (only when var.serverless) ──────────────────────
  # min_acu = 0 enables auto-pause: compute cost $0 while idle, ~15s resume
  # on the next connection. Intended for dev/qa — prod should keep min > 0.
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless ? [1] : []
    content {
      min_capacity             = var.serverless_min_acu
      max_capacity             = var.serverless_max_acu
      seconds_until_auto_pause = var.serverless_min_acu == 0 ? var.serverless_auto_pause_seconds : null
    }
  }

  # ── Encryption — always on, always the account's existing RDS CMK ─────────
  storage_encrypted = true
  kms_key_id        = local.kms_key_arn

  # ── FinOps: storage model (standard vs Aurora I/O-Optimized) ──────────────
  # null = provider default (standard). "aurora-iopt1" caps and flattens I/O
  # cost for I/O-heavy workloads. Opt-in via var.storage_type.
  storage_type = local.storage_type_effective

  # ── AuthN hardening ───────────────────────────────────────────────────────
  # IAM DB auth lets workloads (lambda/ecs/eks) connect with rds-db:connect
  # tokens instead of static passwords.
  iam_database_authentication_enabled = true

  # ── Backups / lifecycle protection ────────────────────────────────────────
  backup_retention_period      = local.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = local.deletion_protection
  skip_final_snapshot          = !local.is_prod_like
  final_snapshot_identifier    = "${local.cluster_name}-final"

  # ── Observability ─────────────────────────────────────────────────────────
  enabled_cloudwatch_logs_exports = ["postgresql"]

  allow_major_version_upgrade = false
  apply_immediately           = local.apply_immediately

  tags = merge(local.tags, { Name = local.cluster_name })

  lifecycle {
    # Joining/leaving a global database is a deliberate day-2 operation
    # (see enable_global_database) — never an accidental plan side-effect.
    ignore_changes = [global_cluster_identifier, replication_source_identifier]

    # Guardrail: the admin credential is mandatory except on global-secondary
    # clusters (which inherit it). Fails at plan time if ci.yml did not inject
    # TF_VAR_master_password from BeyondTrust (secret_titles input missing).
    precondition {
      condition     = local.is_global_secondary || length(var.master_password) >= 16
      error_message = "master_password is required (>= 16 chars). It must be injected as TF_VAR_master_password from BeyondTrust Secrets Safe via the ci.yml secret_titles input — never hardcoded."
    }

    # Serverless v2 sanity: the ceiling must be above the floor.
    precondition {
      condition     = !var.serverless || var.serverless_max_acu >= var.serverless_min_acu
      error_message = "serverless_max_acu must be >= serverless_min_acu."
    }

    # Auto-pause (min_acu = 0) trades cost for a ~15s resume delay on the
    # first connection — never acceptable in prod-like environments.
    precondition {
      condition     = !(var.serverless && var.serverless_min_acu == 0 && local.is_prod_like)
      error_message = "serverless_min_acu = 0 (auto-pause) is not allowed in preprod/prod/dr — set a floor of at least 0.5 ACU."
    }

    # 🛡️ FinOps guard rail: the serverless ceiling cannot exceed the
    # per-environment cap (prevents a runaway cost ceiling, e.g. 256 ACU in dev).
    precondition {
      condition     = !var.serverless || var.serverless_max_acu <= local.serverless_max_acu_ceiling
      error_message = "serverless_max_acu (${var.serverless_max_acu}) exceeds the ${var.ambiente} ceiling of ${local.serverless_max_acu_ceiling} ACU. Raise the ceiling in the module (locals.serverless_max_acu_ceiling) if the workload truly needs it."
    }

    # Auto-pause (min_acu = 0) requires a recent engine — fail at PLAN instead
    # of a late apply-time API error. Minima: 16.3 / 15.7 / 14.12.
    precondition {
      condition = !(var.serverless && var.serverless_min_acu == 0) || (
        local.engine_major > 16 ||
        (local.engine_major == 16 && local.engine_minor >= 3) ||
        (local.engine_major == 15 && local.engine_minor >= 7) ||
        (local.engine_major == 14 && local.engine_minor >= 12)
      )
      error_message = "serverless_min_acu = 0 (auto-pause) requires engine >= 16.3 / 15.7 / 14.12. Current engine_version is ${var.engine_version}."
    }

    # 🛡️ Reliability guard rail: prod/dr must physically span both AZs. Catches
    # a var.instances override that accidentally pins every instance to one AZ.
    precondition {
      condition     = !contains(["prod", "dr"], var.ambiente) || local.instance_az_count >= 2
      error_message = "prod/dr must span both AZs (a and b). The current instances map only spans ${local.instance_az_count} AZ. Provide a reader in the other AZ."
    }
  }

  depends_on = [terraform_data.guards, aws_cloudwatch_log_group.postgresql]
}

# ── Cluster instances ─────────────────────────────────────────────────────────
# Map-driven: son repos add readers or change the class per instance via
# var.instances without any module change. Keys become the name suffix
# ("01", "02", "analytics"...). promotion_tier drives failover order.
resource "aws_rds_cluster_instance" "this" {
  for_each = local.instances

  identifier         = "rds-aw-${local.region_short}-${var.service}-${var.workload}-${each.key}-${var.ambiente}"
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  instance_class          = each.value.instance_class
  availability_zone       = local.az_name_by_selector[each.value.az]
  promotion_tier          = each.value.promotion_tier
  db_parameter_group_name = aws_db_parameter_group.this.name

  publicly_accessible        = false
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  ca_cert_identifier         = var.ca_cert_identifier
  apply_immediately          = local.apply_immediately

  # ── Observability ─────────────────────────────────────────────────────────
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? local.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  monitoring_interval                   = local.monitoring_interval
  monitoring_role_arn                   = local.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  tags = merge(local.tags, {
    Name = "rds-aw-${local.region_short}-${var.service}-${var.workload}-${each.key}-${var.ambiente}"
  })
}

# ── Global Database (opt-in, prod primary side) ───────────────────────────────
# Created FROM the existing prod cluster (no recreation). The dr environment
# then joins by setting global_cluster_identifier = "gdb-aw-{service}-{workload}".
# Order matters and is guaranteed by the promotion chain: prod applies first,
# dr applies after.
resource "aws_rds_global_cluster" "this" {
  count = var.enable_global_database && var.ambiente == "prod" ? 1 : 0

  global_cluster_identifier    = local.global_cluster_name
  source_db_cluster_identifier = aws_rds_cluster.this.arn
  force_destroy                = false

  lifecycle {
    # Engine version is managed on the member clusters; the global wrapper
    # reports it and must not fight them.
    ignore_changes = [engine_version]
  }
}
