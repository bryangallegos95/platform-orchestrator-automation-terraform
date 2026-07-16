# modules/integration/appflow/locals.tf
#
# Centralised naming convention and tag factory.
#
# Naming pattern reference:
#   Flow             : appflow-aw-{region_short}-{service}-{workload}-{ambiente}
#   IAM Role         : iam-role-aw-{region_short}-{service}-{workload}-appflow-{ambiente}
#   Connector Profile: connector-aw-{region_short}-{service}-{workload}-{ambiente}

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Resource names ────────────────────────────────────────────────────────
  flow_name              = "appflow-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  role_name              = "iam-role-aw-${local.region_short}-${var.service}-${var.workload}-appflow-${var.ambiente}"
  connector_profile_name = "connector-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"

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
