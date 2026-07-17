# modules/compliance/s3-compliance-reports/locals.tf
#
# Centralised naming convention and tag factory.
#
# Naming pattern reference:
#   Bucket: s3-aw-{region_short}-compliance-reports-{ambiente}
#
# Folder structure inside the bucket:
#   prowler/{account_id}/{date}/               — Prowler CIS 2.0 reports
#   prowler/{account_id}/{date}/html/          — Human-readable HTML
#   prowler/{account_id}/{date}/json/          — Machine-readable JSON
#   finops/{ou_name}/{date}/                   — FinOps weekly reports
#   tag-audit/{account_id}/{date}/             — Tag compliance reports
#   deployments/{repo_name}/{env}/{date}.md    — Deployment records

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Resource names ────────────────────────────────────────────────────────
  bucket_name = "s3-aw-${local.region_short}-compliance-reports-${var.ambiente}"

  # ── KMS resolution ────────────────────────────────────────────────────────
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.s3[0].target_key_arn

  # ── Logging prefix ────────────────────────────────────────────────────────
  logging_prefix = "s3-access-logs/compliance-reports-${var.ambiente}/"

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
