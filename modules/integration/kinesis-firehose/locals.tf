# modules/integration/kinesis-firehose/locals.tf
#
# Centralised naming convention and tag factory.
#
# Naming pattern reference:
#   Stream     : kdf-aw-{region_short}-{service}-{workload}-{ambiente}
#   IAM Role   : iam-role-aw-{region_short}-{service}-{workload}-firehose-{ambiente}
#   CW Group   : /aws/kinesisfirehose/kdf-aw-{region_short}-{service}-{workload}-{ambiente}
#   CW Stream  : S3Delivery

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Resource names ────────────────────────────────────────────────────────
  stream_name    = "kdf-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  role_name      = "iam-role-aw-${local.region_short}-${var.service}-${var.workload}-firehose-${var.ambiente}"
  log_group_name = "/aws/kinesisfirehose/${local.stream_name}"
  log_stream_name = "S3Delivery"

  # ── Schema region (defaults to stream region) ────────────────────────────
  schema_region = var.schema_region != "" ? var.schema_region : var.aws_region

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
