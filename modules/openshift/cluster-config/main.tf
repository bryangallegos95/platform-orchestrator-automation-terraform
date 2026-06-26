# modules/openshift/cluster-config/main.tf
#
# Day-1 control-plane configuration via OCM (no kubeconfig required).
# Configures Identity Providers on an existing ROSA HCP cluster using the
# rhcs provider + RHCS_TOKEN. Terraform state is stored encrypted with the
# cluster's KMS key (accepted by Seguridad — client_secret sensitive field).
#
# ── IDPs configured ───────────────────────────────────────────────────────────
# 1. htpasswd   — local admin user ("admin" / var.htpasswd_password).
#                 ONLY non-prod environments (dev/qa/preprod).
#                 Gated by var.enable_htpasswd = false on prod/dr.
#                 Used exclusively for Day-2 bootstrapping (oc login admin/changeme).
#                 Must be removed or disabled before any prod promotion.
#
# 2. openid     — EntraID (Azure AD) federation for the full organisation.
#                 Applied to ALL environments (dev through dr).
#                 client_secret is marked sensitive in the provider schema;
#                 it is persisted in state encrypted with the cluster KMS key.
#
# ── Re-run safety ────────────────────────────────────────────────────────────
# Both resources are idempotent via the rhcs provider. Re-runs skip already-
# created IDPs and retry only failed ones (same pattern as the cluster unit).
#
# ── Provider note ─────────────────────────────────────────────────────────────
# rhcs provider authenticates via RHCS_TOKEN env var (GitHub Secret).
# No AWS credentials are needed — OCM is contacted directly.

# ── htpasswd IDP (non-prod only) ─────────────────────────────────────────────
# count = 0 on prod/dr → resource is not created, not visible to OCM.
# The enable_htpasswd gate is the ONLY protection; no other guard exists.
# Terragrunt invocations for prod/dr MUST set enable_htpasswd = false.
resource "rhcs_identity_provider" "htpasswd" {
  count = var.enable_htpasswd ? 1 : 0

  cluster = var.cluster_id
  name    = "htpasswd-local"

  htpasswd = {
    users = [
      {
        username = var.htpasswd_username
        password = var.htpasswd_password   # sensitive in provider schema
      }
    ]
  }
}

# ── EntraID openid IDP (all environments) ─────────────────────────────────────
# issuer follows the standard Azure AD OIDC v2.0 pattern.
# claims: preferred_username → email/UPN; groups → group membership claim.
#
# Prerequisites in Azure (already done — credentials obtained):
#   - App Registration with redirect URI: https://oauth-openshift.apps.<cluster>/oauth2callback/EntraID
#   - "groups" claim enabled in token configuration
#   - The AD group (var.entra_ad_group_id) granted access to the application
resource "rhcs_identity_provider" "entra_id" {
  cluster = var.cluster_id
  name    = "EntraID"

  openid = {
    client_id     = var.entra_client_id
    client_secret = var.entra_client_secret   # sensitive — persisted in KMS-encrypted state

    # Standard Azure AD OIDC v2.0 issuer URL
    issuer = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0"

    claims = {
      # Map the Azure UPN to OpenShift's preferred_username
      preferred_username = ["preferred_username", "email"]
      # Map Azure email claim
      email              = ["email"]
      # Map Azure display name
      name               = ["name"]
      # Map the groups claim — requires "groups" claim configured in App Registration
      groups             = ["groups"]
    }

    # Request the additional 'email' scope beyond the default 'openid'
    extra_scopes = ["email", "profile"]
  }
}
