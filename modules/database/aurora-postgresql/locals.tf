# modules/database/aurora-postgresql/locals.tf
#
# Centralised naming convention, HARDENING CONTRACT and tag factory.
# ALL resource names are derived from here — never hardcoded in main.tf.
#
# HARDENING CONTRACT (why this file looks the way it does):
#   🔒 LOCKED     — security invariants, identical in every environment, NOT
#                   overridable by son repos (cifrado, force_ssl, pgaudit/logging
#                   baseline, IAM auth, no public access, port 15432).
#   🛡️ GUARD-RAIL — protective controls with an environment FLOOR that a son
#                   repo may RAISE but never LOWER (deletion protection,
#                   PITR retention, Enhanced Monitoring, multi-AZ, apply timing,
#                   serverless ACU ceiling).
#   🎚️ FREE       — son-repo self-service within the guard rails (ACUs under the
#                   ceiling, extra readers, non-security parameters, tags...).
#
# Naming pattern reference:
#   Cluster        : rds-aw-{region_short}-{workload}-{ambiente}
#   Instance       : rds-aw-{region_short}-{workload}-{nn}-{ambiente}
#   Subnet group   : sng-aw-{region_short}-{workload}-{ambiente}
#   Cluster PG     : cpg-aw-{region_short}-{workload}-{ambiente}
#   Instance PG    : dpg-aw-{region_short}-{workload}-{ambiente}
#   SG             : sgp-aw-{region_short}-{workload}-{ambiente}
#   Monitoring role: iam-role-aw-{region_short}-{workload}-rds-monitoring-{ambiente}
#   Global cluster : gdb-aw-{workload}  (region-agnostic by design)
#   VPC lookup     : vpc-aw-{region_short}-{vpc_service}-{ambiente}

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── VPC discovery service ────────────────────────────────────────────────
  # If vpc_discovery_service is set, use it to find the Spoke VPC; otherwise
  # fall back to var.workload. This allows the module to deploy into a VPC
  # whose service tag differs from the workload name.
  vpc_service = var.vpc_discovery_service != "" ? var.vpc_discovery_service : var.workload

  # ── Discovery targets (contract with modules/networking/vpc) ─────────────
  vpc_name_to_discover = "vpc-aw-${local.region_short}-${local.vpc_service}-${var.ambiente}"

  # ── Resource names ────────────────────────────────────────────────────────
  cluster_name         = "rds-aw-${local.region_short}-${var.workload}-${var.ambiente}"
  subnet_group_name    = "sng-aw-${local.region_short}-${var.workload}-${var.ambiente}"
  cluster_pg_name      = "cpg-aw-${local.region_short}-${var.workload}-${var.ambiente}"
  instance_pg_name     = "dpg-aw-${local.region_short}-${var.workload}-${var.ambiente}"
  sg_name              = "sgp-aw-${local.region_short}-${var.workload}-${var.ambiente}"
  monitoring_role_name = "iam-role-aw-${local.region_short}-${var.workload}-rds-monitoring-${var.ambiente}"
  global_cluster_name  = "gdb-aw-${var.workload}"

  # 🔒 LOCKED — engine port. Security standard: 15432 (not the default 5432).
  # Applied to the cluster AND the Security Group ingress rules. Not exposed
  # to son repos — the platform owns the listening port.
  db_port = 15432

  # ── KMS resolution ────────────────────────────────────────────────────────
  # Explicit ARN wins; otherwise resolve the account's pre-existing CMK by
  # alias (see data.tf). The module never creates keys.
  kms_key_arn                 = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.rds[0].target_key_arn
  cloudwatch_logs_kms_key_arn = var.cloudwatch_logs_kms_key_arn != "" ? var.cloudwatch_logs_kms_key_arn : data.aws_kms_alias.cwlogs[0].target_key_arn

  # ── Managed PostgreSQL log group (see logs.tf) ───────────────────────────
  postgresql_log_group_name = "/aws/rds/cluster/${local.cluster_name}/postgresql"
  # 🛡️ GUARD-RAIL — retention floor by environment; a son repo may set a longer
  # retention but the module keeps the environment default when unset.
  default_log_retention_days = contains(["prod", "dr"], var.ambiente) ? 365 : (var.ambiente == "preprod" ? 90 : 30)
  log_retention_days         = coalesce(var.cloudwatch_log_retention_days, local.default_log_retention_days)

  # ── Environment posture ───────────────────────────────────────────────────
  # prod-like environments get the protective controls automatically.
  is_prod_like = contains(["preprod", "prod", "dr"], var.ambiente)

  # ── 🛡️ Topology: single-AZ (noprod) vs multi-AZ (prod/dr) — LOCKED in prod/dr
  # prod/dr are ALWAYS multi-AZ (a son repo cannot downgrade to single-AZ).
  # Elsewhere the son repo may opt UP to multi-AZ (default single).
  multi_az = contains(["prod", "dr"], var.ambiente) ? true : coalesce(var.multi_az, false)

  # ── 🎚️ FinOps: storage model + serverless ACU ceiling ────────────────────
  # I/O-Optimized is opt-in; "standard" maps to the provider default (null) to
  # avoid a perpetual diff.
  storage_type_effective = var.storage_type == "aurora-iopt1" ? "aurora-iopt1" : null

  # 🛡️ GUARD-RAIL — per-environment ceiling on serverless_max_acu. Prevents a
  # runaway cost ceiling (e.g. 256 ACU in dev). Enforced by a precondition in
  # main.tf.
  serverless_max_acu_ceiling = {
    dev     = 8
    qa      = 8
    preprod = 16
    prod    = 64
    dr      = 64
  }[var.ambiente]

  # Serverless v2: every instance defaults to db.serverless and the cluster
  # gets a serverlessv2_scaling_configuration block (see main.tf). Mixed
  # clusters remain possible via per-instance instance_class overrides.
  default_instance_class = var.serverless ? "db.serverless" : var.instance_class

  # Default instance topology. Son repos override/extend via var.instances
  # (add readers, change class per instance) without touching the module.
  default_instances = local.multi_az ? {
    "01" = { instance_class = local.default_instance_class, az = "a", promotion_tier = 0 }
    "02" = { instance_class = local.default_instance_class, az = "b", promotion_tier = 1 }
    } : {
    "01" = { instance_class = local.default_instance_class, az = "a", promotion_tier = 0 }
  }

  # Effective instance map — var.instances (if provided) replaces the default
  # topology entirely. Per-instance nulls fall back to module-level defaults.
  instances = {
    for k, v in(length(var.instances) > 0 ? var.instances : local.default_instances) :
    k => {
      instance_class = coalesce(v.instance_class, local.default_instance_class)
      az             = coalesce(v.az, "a")
      promotion_tier = coalesce(v.promotion_tier, 1)
    }
  }

  # Number of distinct AZs the effective topology spans (used by the prod
  # multi-AZ precondition in main.tf).
  instance_az_count = length(distinct([for k, v in local.instances : v.az]))

  # AZ selector → discovered subnet's AZ name (physical placement).
  az_name_by_selector = {
    a = data.aws_subnet.bdd_a.availability_zone
    b = data.aws_subnet.bdd_b.availability_zone
  }

  # ── Global Database (prod ↔ dr replication, opt-in) ──────────────────────
  # Secondary clusters join an existing global cluster and must NOT define
  # master credentials or database name (inherited from the primary).
  is_global_secondary = var.global_cluster_identifier != ""

  # Cross-account Global Database: when source_account_id is set, the
  # global_cluster_identifier must be an ARN (not just the identifier name)
  # because AWS requires ARN format for cross-account membership.
  # Same-account: just the identifier name suffices.
  effective_global_cluster_identifier = (
    local.is_global_secondary
    ? (
      var.source_account_id != ""
      ? "arn:aws:rds::${var.source_account_id}:global-cluster:${var.global_cluster_identifier}"
      : var.global_cluster_identifier
    )
    : null
  )

  # ── 🛡️ Protective controls — LOCKED in prod-like, guard-railed elsewhere ──
  #
  # deletion_protection:
  #   preprod/prod/dr → ALWAYS on (a son repo cannot disable it).
  #   dev/qa          → default ON (protects "official" dev/qa from accidental
  #                     teardown / lost work); a son repo can set it to false
  #                     for genuinely EPHEMERAL clusters.
  deletion_protection = local.is_prod_like ? true : coalesce(var.deletion_protection, true)

  # backup_retention_period (PITR):
  #   Floor of 35 days in prod/dr, 7 days elsewhere. A son repo may RAISE it
  #   (up to the Aurora max of 35) but never below the floor.
  backup_retention_floor  = contains(["prod", "dr"], var.ambiente) ? 35 : 7
  backup_retention_period = max(local.backup_retention_floor, coalesce(var.backup_retention_period, local.backup_retention_floor))

  # Enhanced Monitoring:
  #   prod-like → ALWAYS on (>= 60s; a son repo cannot disable it, but may pick
  #   a finer granularity). dev/qa → off unless the son repo opts in.
  monitoring_interval = (
    local.is_prod_like
    ? (coalesce(var.monitoring_interval, 60) == 0 ? 60 : coalesce(var.monitoring_interval, 60))
    : coalesce(var.monitoring_interval, 0)
  )

  # apply_immediately:
  #   prod-like → ALWAYS false (changes wait for the maintenance window — change
  #   control). dev/qa → true unless overridden.
  apply_immediately = local.is_prod_like ? false : coalesce(var.apply_immediately, true)

  # ── Engine / parameter-group family ───────────────────────────────────────
  # Major/minor parsed once — used by the family derivation and the auto-pause
  # engine-floor precondition (main.tf).
  engine_major = tonumber(split(".", var.engine_version)[0])
  engine_minor = tonumber(split(".", var.engine_version)[1])

  # Family derived from the engine major version unless explicitly overridden
  # (son repos can change family + version together via inputs).
  db_family = (
    var.db_family != ""
    ? var.db_family
    : "aurora-postgresql${local.engine_major}"
  )

  # ── 🔒 Parameter factory — security baseline is LOCKED ────────────────────
  # These parameter names are the security/audit baseline. They are:
  #   1. rejected if a son repo tries to set them (validation in variables.tf), and
  #   2. merged LAST below, so the baseline wins even if (1) is ever bypassed.
  # Son repos may still ADD non-protected parameters (work_mem, max_connections…).
  base_cluster_parameters = {
    "rds.force_ssl"              = { value = "1", apply_method = "immediate" }
    "log_connections"            = { value = "1", apply_method = "immediate" }
    "log_disconnections"         = { value = "1", apply_method = "immediate" }
    "log_statement"              = { value = "ddl", apply_method = "immediate" }
    "log_min_duration_statement" = { value = "5000", apply_method = "immediate" }
    "shared_preload_libraries"   = { value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
    "pgaudit.log"                = { value = "ddl,role", apply_method = "immediate" }
  }

  # Names a son repo is NOT allowed to override (referenced by the validation
  # in variables.tf).
  protected_parameter_names = keys(local.base_cluster_parameters)

  # Son params first, security baseline LAST → baseline always wins.
  cluster_parameters = merge(
    { for p in var.cluster_parameters : p.name => { value = p.value, apply_method = p.apply_method } },
    local.base_cluster_parameters
  )

  instance_parameters = {
    for p in var.instance_parameters : p.name => { value = p.value, apply_method = p.apply_method }
  }

  # ── Tag factory ─────────────────────────────────────────────────────────
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
    Ambiente           = var.ambiente
    ManagedBy          = "terraform"
  }

  # Final merged tag map — used everywhere
  tags = merge(local.mandatory_tags, var.extra_tags)
}
