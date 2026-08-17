# modules/database/dynamodb/locals.tf
#
# Centralised naming, HARDENING CONTRACT and tag factory.
# ALL table names are derived from here — never hardcoded in main.tf.
#
# HARDENING CONTRACT (why this file looks the way it does):
#   🔒 LOCKED     — security invariants, identical in every environment, NOT
#                   overridable by son repos: SSE-KMS with an account CMK (never
#                   the AWS-owned key), the fixed 5-table catalog, the key schema
#                   of every table, Streams on logs/applications/services,
#                   prevent_destroy on logs.
#   🛡️ GUARD-RAIL — protective controls with an environment FLOOR a son repo may
#                   RAISE but never LOWER: deletion protection, PITR, TTL
#                   retention window, Auto Scaling capacity ceiling.
#   🎚️ FREE       — son-repo self-service within the guard rails: billing_mode,
#                   capacities under the ceiling, TTL attribute name, tags.
#
# Naming pattern (reference implementation, CL-LLD-DAT-01 §10.1):
#   logs           : {name_prefix}-logs
#   log-payloads   : {name_prefix}-log-payloads
#   applications   : {name_prefix}-applications
#   services       : {name_prefix}-services
#   wait-logs      : {name_prefix}-wait-logs
# See the README for the pending contrast against the corporate convention.

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Environment posture ───────────────────────────────────────────────────
  # prod-like environments get the protective controls automatically.
  is_prod_like = contains(["uat", "prod"], var.ambiente)

  # ── KMS resolution ────────────────────────────────────────────────────────
  # 🔒 LOCKED — explicit ARN wins; otherwise resolve the account's pre-existing
  # CMK by alias (see data.tf). The module never creates keys, and the tables are
  # never left on the AWS-owned default key.
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.dynamodb[0].target_key_arn

  # ── Table names ───────────────────────────────────────────────────────────
  table_names = {
    logs         = "${var.name_prefix}-logs"
    payloads     = "${var.name_prefix}-log-payloads"
    applications = "${var.name_prefix}-applications"
    services     = "${var.name_prefix}-services"
    wait_logs    = "${var.name_prefix}-wait-logs"
  }

  # ── 🛡️ Protective controls — LOCKED in prod-like, guard-railed elsewhere ──
  #
  # deletion_protection:
  #   uat/prod  → ALWAYS on (a son repo cannot disable it).
  #   dev/test  → default ON; a son repo may set it false for genuinely
  #               ephemeral stacks.
  # CL-LLD-DAT-01 §9.3 lists deletion_protection_enabled = true on every table as
  # an auditable control, not a convenience.
  deletion_protection = local.is_prod_like ? true : coalesce(var.deletion_protection, true)

  # point_in_time_recovery:
  #   uat/prod → ALWAYS on. dev/test → default ON, may be disabled.
  point_in_time_recovery = local.is_prod_like ? true : coalesce(var.point_in_time_recovery, true)

  # ── 🛡️ TTL retention window ───────────────────────────────────────────────
  # Floor per environment (CL-LLD-ARQ-C0); a son repo may RAISE it but never go
  # below. uat comparte el piso de prod por diseño: es el ambiente de aceptación
  # y debe reproducir la ventana caliente productiva.
  # TODO: decisión de negocio pendiente (CL-LLD-DAT-01 §12.2 #4) — 30 vs 90 días
  # de ventana caliente, ~USD 123/mes de diferencia. El piso de 30 días en
  # uat/prod es el mínimo defendible ante auditoría mientras Negocio/Operaciones
  # no confirme la ventana definitiva; si se confirma 90, sube el default sin
  # tocar este piso.
  ttl_retention_floor = {
    dev  = 7
    test = 15
    uat  = 30 # "igual que prod" — mismo valor que el piso de prod
    prod = 30
  }[var.ambiente]

  ttl_retention_days = max(local.ttl_retention_floor, var.ttl_retention_days)

  # ── 🛡️ FinOps: per-environment Auto Scaling ceiling ───────────────────────
  # Prevents a runaway cost ceiling (e.g. 1.500 WCU provisioned in dev). The
  # requested maximum is CLAMPED rather than rejected, so the module default
  # (sized for production, §8.2) stays usable in every environment without the
  # son repo having to restate it.
  write_capacity_ceiling = {
    dev  = 200
    test = 200
    uat  = 500
    prod = 1500
  }[var.ambiente]

  read_capacity_ceiling = {
    dev  = 200
    test = 200
    uat  = 500
    prod = 1000
  }[var.ambiente]

  write_capacity_max = min(var.write_capacity_max, local.write_capacity_ceiling)
  read_capacity_max  = min(var.read_capacity_max, local.read_capacity_ceiling)

  # ── Billing mode / capacity resolution ────────────────────────────────────
  # 🎚️ FREE — capacities only apply in PROVISIONED mode; PAY_PER_REQUEST must
  # leave them null or the provider rejects the table.
  is_provisioned = var.billing_mode == "PROVISIONED"
  read_capacity  = local.is_provisioned ? var.read_capacity : null
  write_capacity = local.is_provisioned ? var.write_capacity : null

  # Auto Scaling on the logs table only, and only in PROVISIONED mode. The audit
  # load is sustained and predictable with a known daily seasonality — the exact
  # profile in which On-Demand is uneconomic (CL-LLD-DAT-01 §8.2).
  logs_autoscaling = local.is_provisioned

  # ── Tag factory ─────────────────────────────────────────────────────────
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
    Ambiente           = var.ambiente
    ManagedBy          = "terraform"
  }

  # Final merged tag map — used everywhere.
  tags = merge(local.mandatory_tags, var.extra_tags)
}
