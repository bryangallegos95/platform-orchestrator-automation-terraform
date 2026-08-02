# modules/networking/vpc/locals.tf
#
# Centralised naming convention and tag factory.
# ALL resource names are derived from here — never hardcoded in main.tf.
#
# Naming pattern reference:
#   VPC     : vpc-aw-ue1-{service}-{ambiente}
#   Subnet  : snet-aw-ue1-{service}-private-{tier}-{az}
#   RT      : rt-aw-ue1-{service}-private-{az}
#   TGW Att : tgw-att-aw-ue1-{service}-{ambiente}
#   Flow Log: fl-aw-ue1-{service}-{ambiente}
#   IAM Role: iam-role-aw-ue1-{service}-vpc-flow-logs-{ambiente}
#   CW Group: /aws/vpc/flow-logs/vpc-aw-ue1-{service}-{ambiente}

locals {
  # ── ROSA HCP Enabled ────────────────────────────────────────────────
  rosa_subnet_tags = var.rosa_enabled ? {
    "bancointernacional.ec/rosa"      = "true"
    "bancointernacional.ec/rosa-tier" = "private"
    "bancointernacional.ec/dominio"   = var.service
    "bancointernacional.ec/env"       = var.ambiente
    "kubernetes.io/role/internal-elb" = "1"
  } : {}

  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Resource names ────────────────────────────────────────────────────────
  vpc_name = "vpc-aw-${local.region_short}-${var.service}-${var.ambiente}"

  # Subnets — App tier
  snet_app_a = "snet-aw-${local.region_short}-${var.service}-private-app-a"
  snet_app_b = "snet-aw-${local.region_short}-${var.service}-private-app-b"

  # Subnets — BDD (database) tier
  snet_bdd_a = "snet-aw-${local.region_short}-${var.service}-private-bdd-a"
  snet_bdd_b = "snet-aw-${local.region_short}-${var.service}-private-bdd-b"

  # Subnets — GWLB / API-GW endpoint tier
  snet_gwlb_a = "snet-aw-${local.region_short}-${var.service}-private-gwlb-a"
  snet_gwlb_b = "snet-aw-${local.region_short}-${var.service}-private-gwlb-b"

  # Route tables (one per AZ — all tiers in the same AZ share the same RT)
  rt_private_a = "rt-aw-${local.region_short}-${var.service}-private-a"
  rt_private_b = "rt-aw-${local.region_short}-${var.service}-private-b"

  # TGW attachment
  tgw_attachment_name = "tgw-att-aw-${local.region_short}-${var.service}-${var.ambiente}"

  # Flow Logs
  flow_log_name      = "fl-aw-${local.region_short}-${var.service}-${var.ambiente}"
  flow_log_group     = "/aws/vpc/flow-logs/${local.vpc_name}"
  flow_log_role_name = "iam-role-aw-${local.region_short}-${var.service}-vpc-flow-logs-${var.ambiente}"

  # ── Availability Zones ───────────────────────────────────────────────────
  # Use physical AZ IDs to guarantee Hub↔Spoke alignment across accounts.
  az_id_a = var.az_id_a
  az_id_b = var.az_id_b

  # ── Tag factory ─────────────────────────────────────────────────────────
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
    Ambiente           = var.ambiente
    ManagedBy          = "terraform"
    ou                 = var.service
  }

  # Final merged tag map — used everywhere
  tags = merge(local.mandatory_tags, var.extra_tags)
}
