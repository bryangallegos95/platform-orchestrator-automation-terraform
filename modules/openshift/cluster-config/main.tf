# modules/openshift/cluster-config/main.tf
#
# Day-1 — Configuración de Identity Providers vía OCM (sin kubeconfig).
# Aplica sobre un cluster ROSA HCP existente usando el provider rhcs + RHCS_TOKEN.
#
# IDPs configurados:
#   1. htpasswd  — usuario local admin (dev/qa/preprod únicamente).
#                  Gate: var.enable_htpasswd = false en prod/dr.
#                  Uso exclusivo: oc login bootstrap en Day-2.
#
#   2. openid    — Federación EntraID (Azure AD) para toda la organización.
#                  Aplicado en TODOS los ambientes (dev→dr).
#                  Campos requeridos (ref: docs.redhat.com/rosa/tutorials/cloud-experts-entra-id-idp):
#                    client_id     = Application (client) ID del App Registration
#                    client_secret = Client secret del App Registration (sensitive)
#                    issuer        = https://login.microsoftonline.com/<tenant_id>/v2.0
#
# Origen de variables (todas inyectadas por ci.yml, nunca hardcoded):
#   var.entra_client_id     ← TF_VAR_entra_client_id   (BeyondTrust title: app_id,     via extra_vars)
#   var.entra_client_secret ← TF_VAR_entra_client_secret (BeyondTrust title: client-secret, via secret_titles)
#   var.entra_tenant_id     ← TF_VAR_entra_tenant_id   (BeyondTrust title: tenant-id,  via extra_vars)
#   var.htpasswd_password   ← TF_VAR_htpasswd_password  (BeyondTrust title: htpasswd-password, via secret_titles)
#
# Re-run safety: ambos recursos son idempotentes (provider rhcs).
# Re-runs saltan lo ya creado y reintentan lo fallido.

# ── htpasswd IDP (non-prod únicamente) ───────────────────────────────────────
# count = 0 en prod/dr → no se crea, invisible para OCM.
# El gate enable_htpasswd es la ÚNICA protección — los terragrunt.hcl de
# prod y dr DEBEN tener enable_htpasswd = false.
resource "rhcs_identity_provider" "htpasswd" {
  count = var.enable_htpasswd ? 1 : 0

  cluster = var.cluster_id
  name    = "htpasswd-local"

  htpasswd = {
    users = [
      {
        username = var.htpasswd_username
        password = var.htpasswd_password   # sensitive en el schema del provider
      }
    ]
  }
}

# ── EntraID openid IDP (todos los ambientes) ──────────────────────────────────
#
# Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/tutorials/cloud-experts-entra-id-idp
#
# Prerequisitos Azure (deben estar configurados antes del apply):
#   1. App Registration creado en Azure AD.
#   2. Redirect URI en Azure App Registration:
#        https://oauth-openshift.apps.rosa.<cluster-domain>/oauth2callback/EntraID
#      Para int-dev:
#        https://oauth-openshift.apps.rosa.int-dev.pbdk.p3.openshiftapps.com/oauth2callback/EntraID
#   3. Claim "groups" habilitado en Token configuration del App Registration.
#   4. Grupos de AD asignados con acceso a la aplicación.
#
# Claims mapeados:
#   preferred_username → preferred_username, email (UPN del usuario en Azure)
#   email              → email
#   name               → name (displayName del usuario)
#   groups             → groups (requiere "groups" claim en App Registration)
resource "rhcs_identity_provider" "entra_id" {
  cluster = var.cluster_id
  name    = "EntraID"

  openid = {
    client_id     = var.entra_client_id
    client_secret = var.entra_client_secret   # sensitive — persiste en state cifrado S3 (AES-256)

    # Issuer estándar de Azure AD OIDC v2.0 (endpoint multi-tenant).
    # Soporta tanto cuentas organizacionales como personales.
    issuer = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0"

    claims = {
      # El UPN de Azure (user@bancointernacional.ec) se usa como preferred_username.
      # Fallback a email si preferred_username no está disponible.
      preferred_username = ["preferred_username", "email"]
      email              = ["email"]
      name               = ["name"]
      # Grupos de AD → RBAC en OpenShift.
      # Requiere: Azure App Registration → Token configuration → Groups claim = "All groups"
      groups             = ["groups"]
    }

    # Scopes adicionales más allá de 'openid' (requerido por default).
    # 'email' y 'profile' son necesarios para que los claims email/name
    # estén disponibles en el token.
    extra_scopes = ["email", "profile"]
  }

  # mapping_method = "claim" es el default del provider — no necesita declararse.
  # "claim" mapea identidades a usuarios existentes o crea usuarios nuevos
  # basándose en el claim (comportamiento correcto para federación empresarial).
}
