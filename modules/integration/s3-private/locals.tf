# modules/integration/s3-private/locals.tf
#
# Centralised naming convention and tag factory.
# ALL resource names are derived from here — never hardcoded in main.tf.
#
# Naming pattern reference:
#   Bucket     : s3-aw-{region_short}-{service}-{workload}-{ambiente}
#   Log prefix : s3-access-logs/{service}-{workload}-{ambiente}/

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Resource names ────────────────────────────────────────────────────────
  bucket_name = "s3-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"

  # ── KMS resolution ────────────────────────────────────────────────────────
  # Explicit ARN wins; otherwise resolve by alias (account baseline).
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.s3[0].target_key_arn

  # ── Environment posture ───────────────────────────────────────────────────
  is_prod_like = contains(["preprod", "prod", "dr"], var.ambiente)

  # ── Logging prefix ───────────────────────────────────────────────────────
  logging_prefix = var.logging_prefix != "" ? var.logging_prefix : "s3-access-logs/${var.service}-${var.workload}-${var.ambiente}/"

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
