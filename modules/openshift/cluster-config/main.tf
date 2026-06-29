# modules/openshift/cluster-config/main.tf
#
# Day-1 — Identity Provider configuration via OCM (no kubeconfig).
# Applies to an existing ROSA HCP cluster using the rhcs provider + RHCS_TOKEN.
#
# IDPs configured:
#   1. htpasswd  — local admin user (dev/qa/preprod only).
#                  Gate: var.enable_htpasswd = false for prod/dr.
#                  Sole use: oc login bootstrap during Day-2.
#
#   2. openid    — EntraID (Azure AD) federation for the whole organization.
#                  Applied in ALL environments (dev→dr).
#
# ── CUSTOM INGRESS: NOT HERE ──────────────────────────────────────────────────
# The bank-domain ingress is a SECONDARY IngressController ('custom') managed by
# GitOps in iac-gitops-platform-baseline (base/ingress/). It is NOT configured by
# Terraform. The previous rhcs_default_ingress approach was removed because:
#   - It modified the DEFAULT router (platform's ROSA domain), breaking the
#     "platform uses the ROSA default router" requirement.
#   - The proven production pattern is a SEPARATE 'custom' IngressController with
#     its own NLB + multi-SAN cert + routeSelector type=custom sharding.
# The TLS cert secret (custom-ingress-tls) is created by the Day-2 workflow
# (orchestrator-cluster-config.yml Step B) via the BeyondTrust 5-step flow.
#
# Variable origin (all injected by ci.yml, never hardcoded):
#   var.entra_client_id      ← TF_VAR_entra_client_id      (BeyondTrust title: app_id)
#   var.entra_client_secret  ← TF_VAR_entra_client_secret  (BeyondTrust title: client-secret)
#   var.entra_tenant_id      ← TF_VAR_entra_tenant_id      (BeyondTrust title: tenant-id)
#   var.htpasswd_password    ← TF_VAR_htpasswd_password    (BeyondTrust title: admin_user → .Password)
#
# Re-run safety: all resources are idempotent (rhcs provider). Re-runs skip what
# already exists and retry what failed.

# ── htpasswd IDP (non-prod only) ──────────────────────────────────────────────
resource "rhcs_identity_provider" "htpasswd" {
  count = var.enable_htpasswd ? 1 : 0

  cluster = var.cluster_id
  name    = "htpasswd-local"

  htpasswd = {
    users = [
      {
        username = var.htpasswd_username
        password = var.htpasswd_password
      }
    ]
  }
}

# ── EntraID openid IDP (all environments) ─────────────────────────────────────
#
# Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/tutorials/cloud-experts-entra-id-idp
#
# name = "OpenID" → the Azure App Registration Redirect URI MUST be (ROSA HCP format):
#   https://oauth.<cluster>.<domain>.p3.openshiftapps.com:443/oauth2callback/OpenID
# The IDP name and the last segment of the Redirect URI MUST match ("OpenID").
# NOTE: ROSA HCP uses the oauth.<cluster>.<domain> route format — NOT the ARO
# format (oauth-openshift.apps.rosa...). Confirm the real domain per cluster with:
#   rosa describe cluster -c <cluster> -o json | jq -r '.console.url'
resource "rhcs_identity_provider" "entra_id" {
  cluster = var.cluster_id
  name    = "OpenID"

  openid = {
    client_id     = var.entra_client_id
    client_secret = var.entra_client_secret
    issuer        = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0"

    claims = {
      preferred_username = ["preferred_username", "email"]
      email              = ["email"]
      name               = ["name"]
      groups             = ["groups"]
    }

    extra_scopes = ["email", "profile"]
  }
}
