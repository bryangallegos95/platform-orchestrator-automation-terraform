# modules/identity/irsa-role/locals.tf
#
# Centralised naming, HARDENING CONTRACT, trust policy construction, tag factory.
#
# HARDENING CONTRACT:
#   LOCKED     — Trust uses StringEquals (never StringLike with wildcards),
#                audience locked to sts.amazonaws.com, SourceAccount condition,
#                max session 3600s (1 hour — short-lived credentials only),
#                IAM path /irsa/ (enables IAM policy scoping + audit filtering),
#                role naming convention enforced.
#   GUARD-RAIL — max_session_duration ceiling (3600s), permission boundary opt-in.
#   FREE       — N roles via map, N service accounts per role, inline/managed
#                policies (son-repo defines what each role can do).
#
# Naming pattern:
#   Role: irsa-aw-{region_short}-{workload}-{role_key}-{ambiente}
#   (Simplified from v2.5.0 — removes service/funcionalidad to stay within IAM 64-char limit)

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── OIDC provider ────────────────────────────────────────────────────────
  oidc_provider_arn = data.aws_iam_openid_connect_provider.rosa.arn
  oidc_issuer_url   = var.oidc_issuer_url

  # ── 🔒 LOCKED — IAM path for all IRSA roles ──────────────────────────────
  # Using a dedicated path enables:
  #   - IAM policy conditions: arn:aws:iam::*:role/irsa/*
  #   - Audit: list-roles --path-prefix /irsa/
  #   - Permission boundaries scoped to /irsa/ path
  iam_path = "/irsa/"

  # ── 🔒 LOCKED — Max session duration ceiling ─────────────────────────────
  max_session_ceiling = 3600

  # ── Role configurations with naming ──────────────────────────────────────
  # Pattern: irsa-aw-{region}-{workload}-{role_key}-{ambiente}
  # Max length: 12 (prefix) + workload + role_key + ambiente ≤ 64 chars
  roles = {
    for k, v in var.roles : k => {
      role_name = "irsa-aw-${local.region_short}-${var.workload}-${k}-${var.ambiente}"
      description = coalesce(
        v.description,
        "IRSA role for ${k} in ${var.workload} (${var.ambiente})"
      )
      service_accounts        = v.service_accounts
      inline_policies         = v.inline_policies
      managed_policy_arns     = v.managed_policy_arns
      permission_boundary_arn = v.permission_boundary_arn
      max_session_duration    = min(v.max_session_duration, local.max_session_ceiling)

      # 🔒 LOCKED — Trust policy subjects (StringEquals, exact match)
      trust_subjects = [
        for sa in v.service_accounts :
        "system:serviceaccount:${sa.namespace}:${sa.name}"
      ]
    }
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

  tags = merge(local.mandatory_tags, var.extra_tags)
}
