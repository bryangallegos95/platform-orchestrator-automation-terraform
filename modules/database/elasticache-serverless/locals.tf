# modules/database/elasticache-serverless/locals.tf
#
# Centralised naming convention, HARDENING CONTRACT and tag factory.
#
# HARDENING CONTRACT:
#   LOCKED     — TLS in-transit (forced by ElastiCache Serverless — cannot be disabled),
#                CMK at-rest encryption, VPC-only (private subnets), IAM authentication,
#                no public access, Security Group deny-all inbound by default,
#                dual port (6379 write + 6380 read) in SG rules.
#   GUARD-RAIL — snapshot retention floor (prod/dr: 7 days, dev/qa: 1 day),
#                ECPU ceiling per environment, data storage ceiling per environment.
#   FREE       — engine (valkey/redis), major version, usage limits within ceiling,
#                daily snapshot time, user group, extra tags.
#
# Naming pattern:
#   Cache       : ec-aw-{region_short}-{workload}-{ambiente}
#   Subnet group: ecsng-aw-{region_short}-{workload}-{ambiente}
#   SG          : sgp-aw-{region_short}-{workload}-ec-{ambiente}

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Environment posture ───────────────────────────────────────────────────
  is_prod_like = contains(["preprod", "prod", "dr"], var.ambiente)

  # ── VPC discovery service ────────────────────────────────────────────────
  # If vpc_discovery_service is set, use it to find the Spoke VPC; otherwise
  # fall back to var.workload. This allows the module to deploy into a VPC
  # whose service tag differs from the workload name.
  vpc_service = var.vpc_discovery_service != "" ? var.vpc_discovery_service : var.workload

  # ── Resource names ────────────────────────────────────────────────────────
  cache_name        = "ec-aw-${local.region_short}-${var.workload}-${var.ambiente}"
  subnet_group_name = "ecsng-aw-${local.region_short}-${var.workload}-${var.ambiente}"
  sg_name           = "sgp-aw-${local.region_short}-${var.workload}-ec-${var.ambiente}"

  # ── Discovery targets (contract with modules/networking/vpc) ─────────────
  vpc_name_to_discover = "vpc-aw-${local.region_short}-${local.vpc_service}-${var.ambiente}"

  # ── KMS resolution ────────────────────────────────────────────────────────
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.elasticache[0].target_key_arn

  # ── 🔒 LOCKED — Ports. Serverless requires both ports accessible ─────────
  # Port 6379: primary endpoint (read/write)
  # Port 6380: reader endpoint (read-optimized)
  # Both MUST be open in the SG for Serverless to function correctly.
  cache_port_primary = 6379
  cache_port_reader  = 6380

  # ── 🛡️ GUARD-RAIL — Snapshot retention floor per environment ──────────────
  snapshot_retention_floor = local.is_prod_like ? 7 : 1
  snapshot_retention_days  = max(local.snapshot_retention_floor, coalesce(var.snapshot_retention_days, local.snapshot_retention_floor))

  # ── 🛡️ GUARD-RAIL — FinOps ceilings per environment ──────────────────────
  # Prevents runaway cost (e.g. 1M ECPU in dev). Son repos set values WITHIN
  # the ceiling; the module enforces the cap via precondition.
  ecpu_ceiling = {
    dev     = 5000
    qa      = 5000
    preprod = 15000
    prod    = 100000
    dr      = 100000
  }[var.ambiente]

  storage_ceiling_gb = {
    dev     = 5
    qa      = 5
    preprod = 20
    prod    = 100
    dr      = 100
  }[var.ambiente]

  # Effective limits — son repo values capped by ceiling (precondition catches overages)
  effective_max_ecpu    = coalesce(var.max_ecpu_per_second, local.ecpu_ceiling)
  effective_max_storage = coalesce(var.max_data_storage_gb, local.storage_ceiling_gb)

  # ── Tag factory ─────────────────────────────────────────────────────────
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
    Ambiente           = var.ambiente
    ManagedBy          = "terraform"
  }

  tags = merge(local.mandatory_tags, var.extra_tags)
}
