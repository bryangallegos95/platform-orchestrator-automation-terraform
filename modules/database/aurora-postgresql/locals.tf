# modules/database/aurora-postgresql/locals.tf
#
# Centralised naming convention and tag factory — mirrors the EC2/VPC modules.
# ALL resource names are derived from here — never hardcoded in main.tf.
#
# Naming pattern reference:
#   Cluster        : rds-aw-{region_short}-{service}-{workload}-{ambiente}
#   Instance       : rds-aw-{region_short}-{service}-{workload}-{nn}-{ambiente}
#   Subnet group   : sng-aw-{region_short}-{service}-{workload}-{ambiente}
#   Cluster PG     : cpg-aw-{region_short}-{service}-{workload}-{ambiente}
#   Instance PG    : dpg-aw-{region_short}-{service}-{workload}-{ambiente}
#   SG             : sgp-aw-{region_short}-{service}-{workload}-{ambiente}
#   Monitoring role: iam-role-aw-{region_short}-{service}-{workload}-rds-monitoring-{ambiente}
#   Global cluster : gdb-aw-{service}-{workload}  (region-agnostic by design)
#   VPC lookup     : vpc-aw-{region_short}-{service}-{ambiente}

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Discovery targets (contract with modules/networking/vpc) ─────────────
  vpc_name_to_discover = "vpc-aw-${local.region_short}-${var.service}-${var.ambiente}"

  # ── Resource names ────────────────────────────────────────────────────────
  cluster_name         = "rds-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  subnet_group_name    = "sng-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  cluster_pg_name      = "cpg-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  instance_pg_name     = "dpg-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  sg_name              = "sgp-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  monitoring_role_name = "iam-role-aw-${local.region_short}-${var.service}-${var.workload}-rds-monitoring-${var.ambiente}"
  global_cluster_name  = "gdb-aw-${var.service}-${var.workload}"

  # ── KMS resolution ────────────────────────────────────────────────────────
  # Explicit ARN wins; otherwise resolve the account's pre-existing RDS CMK
  # by alias (see data.tf). The module never creates keys.
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.rds[0].target_key_arn

  # ── Environment posture ───────────────────────────────────────────────────
  # prod-like environments get the protective defaults automatically.
  is_prod_like = contains(["preprod", "prod", "dr"], var.ambiente)

  # ── Topology: single-AZ (noprod) vs multi-AZ (prod/dr) ────────────────────
  # Explicit input wins; null = auto → writer+reader across AZs in prod/dr,
  # single writer everywhere else.
  multi_az = var.multi_az != null ? var.multi_az : contains(["prod", "dr"], var.ambiente)

  # Default instance topology. Son repos override/extend via var.instances
  # (add readers, change class per instance) without touching the module.
  default_instances = local.multi_az ? {
    "01" = { instance_class = var.instance_class, az = "a", promotion_tier = 0 }
    "02" = { instance_class = var.instance_class, az = "b", promotion_tier = 1 }
    } : {
    "01" = { instance_class = var.instance_class, az = "a", promotion_tier = 0 }
  }

  # Effective instance map — var.instances (if provided) replaces the default
  # topology entirely. Per-instance nulls fall back to module-level defaults.
  instances = {
    for k, v in(length(var.instances) > 0 ? var.instances : local.default_instances) :
    k => {
      instance_class = coalesce(v.instance_class, var.instance_class)
      az             = coalesce(v.az, "a")
      promotion_tier = coalesce(v.promotion_tier, 1)
    }
  }

  # AZ selector → discovered subnet's AZ name (physical placement).
  az_name_by_selector = {
    a = data.aws_subnet.bdd_a.availability_zone
    b = data.aws_subnet.bdd_b.availability_zone
  }

  # ── Global Database (prod ↔ dr replication, opt-in) ──────────────────────
  # Secondary clusters join an existing global cluster and must NOT define
  # master credentials or database name (inherited from the primary).
  is_global_secondary = var.global_cluster_identifier != ""

  # ── Protective defaults (explicit input wins; null = auto) ───────────────
  deletion_protection = (
    var.deletion_protection != null
    ? var.deletion_protection
    : local.is_prod_like
  )

  backup_retention_period = (
    var.backup_retention_period != null
    ? var.backup_retention_period
    : (contains(["prod", "dr"], var.ambiente) ? 35 : 7)
  )

  # Enhanced Monitoring: 60s granularity in prod-like envs, off in dev/qa.
  monitoring_interval = (
    var.monitoring_interval != null
    ? var.monitoring_interval
    : (local.is_prod_like ? 60 : 0)
  )

  # dev/qa apply changes immediately; prod-like waits for maintenance window.
  apply_immediately = (
    var.apply_immediately != null
    ? var.apply_immediately
    : !local.is_prod_like
  )

  # ── Engine / parameter-group family ───────────────────────────────────────
  # Family derived from the engine major version unless explicitly overridden
  # (son repos can change family + version together via inputs).
  db_family = (
    var.db_family != ""
    ? var.db_family
    : "aurora-postgresql${split(".", var.engine_version)[0]}"
  )

  # ── Parameter factory (CIS/security baseline + son-repo overrides) ───────
  # Son-repo entries win over the baseline on name collision.
  base_cluster_parameters = {
    "rds.force_ssl"              = { value = "1", apply_method = "immediate" }
    "log_connections"            = { value = "1", apply_method = "immediate" }
    "log_disconnections"         = { value = "1", apply_method = "immediate" }
    "log_statement"              = { value = "ddl", apply_method = "immediate" }
    "log_min_duration_statement" = { value = "5000", apply_method = "immediate" }
    "shared_preload_libraries"   = { value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
    "pgaudit.log"                = { value = "ddl,role", apply_method = "immediate" }
  }

  cluster_parameters = merge(
    local.base_cluster_parameters,
    { for p in var.cluster_parameters : p.name => { value = p.value, apply_method = p.apply_method } }
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
