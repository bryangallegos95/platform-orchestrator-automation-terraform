# modules/product/irsa.tf
#
# IRSA (IAM Roles for Service Accounts) building block — conditional deployment.
# This is where NATIVE DEPENDENCIES are resolved: IRSA policies reference
# outputs from Aurora, SQS, and Redis modules.
#
# The compositor builds inline_policies for each IRSA role based on the
# policies.{aurora_connect, sqs_full, redis_connect} flags. Additional
# custom policies can be provided via extra_inline_policies.

locals {
  # ── Build the roles map for the IRSA module ──────────────────────────────
  # Transform the compositor's simplified irsa_roles into the IRSA module's
  # native roles variable format (which expects service_accounts list, etc.)
  irsa_roles_computed = {
    for k, v in var.irsa_roles : k => {
      service_accounts = [{
        namespace = v.namespace
        name      = v.service_account
      }]
      description = v.description
      inline_policies = merge(
        # Native dependency policies — only included when the flag is true
        # AND the dependent building block is actually enabled
        v.policies.aurora_connect && var.aurora_enabled ? {
          "aurora-connect" = local.aurora_connect_policy
        } : {},
        v.policies.sqs_full && var.sqs_enabled ? {
          "sqs-full-access" = local.sqs_full_policy
        } : {},
        v.policies.redis_connect && var.redis_enabled ? {
          "redis-connect" = local.redis_connect_policy
        } : {},
        # Extra custom policies from the son repo
        v.extra_inline_policies,
      )
      managed_policy_arns     = v.extra_managed_policy_arns
      permission_boundary_arn = v.permission_boundary_arn
      max_session_duration    = v.max_session_duration
    }
  }
}

module "irsa" {
  count  = var.irsa_enabled ? 1 : 0
  source = "../identity/irsa-role"

  # ── Identity (common) ───────────────────────────────────────────────────────
  aws_region     = var.aws_region
  service        = var.service
  workload       = var.workload
  funcionalidad  = var.funcionalidad
  ambiente       = var.ambiente
  aws_account_id = var.aws_account_id

  # ── OIDC (ROSA HCP cluster) ────────────────────────────────────────────────
  oidc_issuer_url = var.irsa_config.oidc_issuer_url

  # ── Roles (map-driven, with native dependency policies) ─────────────────────
  roles = local.irsa_roles_computed

  # ── Mandatory tags ──────────────────────────────────────────────────────────
  aplicacion          = var.aplicacion
  propietario_recurso = var.propietario_recurso
  producto            = var.producto
  centro_costo        = var.centro_costo
  extra_tags          = var.extra_tags
}
