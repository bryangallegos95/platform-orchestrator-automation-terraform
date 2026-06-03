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
  # ── Resource names ────────────────────────────────────────────────────────
  vpc_name = "vpc-aw-ue1-${var.service}-${var.ambiente}"

  # Subnets — App tier
  snet_app_a = "snet-aw-ue1-${var.service}-private-app-a"
  snet_app_b = "snet-aw-ue1-${var.service}-private-app-b"

  # Subnets — BDD (database) tier
  snet_bdd_a = "snet-aw-ue1-${var.service}-private-bdd-a"
  snet_bdd_b = "snet-aw-ue1-${var.service}-private-bdd-b"

  # Subnets — GWLB / API-GW endpoint tier
  snet_gwlb_a = "snet-aw-ue1-${var.service}-private-gwlb-a"
  snet_gwlb_b = "snet-aw-ue1-${var.service}-private-gwlb-b"

  # Route tables (one per AZ — all tiers in the same AZ share the same RT)
  rt_private_a = "rt-aw-ue1-${var.service}-private-a"
  rt_private_b = "rt-aw-ue1-${var.service}-private-b"

  # TGW attachment
  tgw_attachment_name = "tgw-att-aw-ue1-${var.service}-${var.ambiente}"

  # Flow Logs
  flow_log_name      = "fl-aw-ue1-${var.service}-${var.ambiente}"
  flow_log_group     = "/aws/vpc/flow-logs/${local.vpc_name}"
  flow_log_role_name = "iam-role-aw-ue1-${var.service}-vpc-flow-logs-${var.ambiente}"

  # ── Availability Zones ───────────────────────────────────────────────────
  az_a = "us-east-1a" # use1-az1
  az_b = "us-east-1b" # use1-az2

  # ── Tag factory ─────────────────────────────────────────────────────────
  # Mandatory tags applied to every resource via merge(local.tags, { Name = ... })
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
    Ambiente           = var.ambiente
    ManagedBy          = "terraform"
    Repositorio        = "platform-orchestrator-automation-terraform"
  }

  # Final merged tag map — used everywhere
  tags = merge(local.mandatory_tags, var.extra_tags)
}
