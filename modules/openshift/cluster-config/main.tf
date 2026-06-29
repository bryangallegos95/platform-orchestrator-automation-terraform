# modules/openshift/cluster-config/main.tf
#
# Day-1 — Configuración de Identity Providers + Custom Ingress vía OCM (sin kubeconfig).
# Aplica sobre un cluster ROSA HCP existente usando el provider rhcs + RHCS_TOKEN.
#
# IDPs configurados:
#   1. htpasswd  — usuario local admin (dev/qa/preprod únicamente).
#                  Gate: var.enable_htpasswd = false en prod/dr.
#                  Uso exclusivo: oc login bootstrap en Day-2.
#
#   2. openid    — Federación EntraID (Azure AD) para toda la organización.
#                  Aplicado en TODOS los ambientes (dev→dr).
#
# Custom Ingress (Day-1 iter.2):
#   3. rhcs_default_ingress — Configura el IngressController DEFAULT de ROSA HCP
#                             con el hostname y TLS cert del banco.
#                  Gate: var.enable_custom_ingress = false hasta que el Day-2
#                         haya creado el secret TLS "custom-apps-cert" en openshift-ingress.
#                  ⚠️ NO crear un segundo IngressController — reutilizar el default.
#                  Prereq: Day-2 Step B debe haber corrido (secret custom-apps-cert existe).
#
# Origen de variables (todas inyectadas por ci.yml, nunca hardcoded):
#   var.entra_client_id      ← TF_VAR_entra_client_id   (BeyondTrust title: app_id)
#   var.entra_client_secret  ← TF_VAR_entra_client_secret (BeyondTrust title: client-secret)
#   var.entra_tenant_id      ← TF_VAR_entra_tenant_id   (BeyondTrust title: tenant-id)
#   var.htpasswd_password    ← TF_VAR_htpasswd_password  (BeyondTrust title: admin_user → .Password)
#
# Re-run safety: todos los recursos son idempotentes (provider rhcs).
# Re-runs saltan lo ya creado y reintentan lo fallido.

# ── htpasswd IDP (non-prod únicamente) ───────────────────────────────────────
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

# ── EntraID openid IDP (todos los ambientes) ──────────────────────────────────
#
# Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/tutorials/cloud-experts-entra-id-idp
#
# name = "OpenID" → Redirect URI en Azure App Registration DEBE ser:
#   https://oauth-openshift.apps.<cluster-domain>/oauth2callback/OpenID
# El name del IDP y el último segmento del Redirect URI DEBEN coincidir.
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

# ── Custom Ingress — Day-1 iter.2 (GATE: enable_custom_ingress) ───────────────
#
# Configura el IngressController DEFAULT de ROSA HCP con:
#   - hostname personalizado del banco (ej: apps.dev.aws.bancointernacional.ec)
#   - TLS cert del banco (secret custom-apps-cert en openshift-ingress)
#
# ⚠️ DEPENDENCY: El Day-2 Step B DEBE haber corrido ANTES de habilitar este recurso.
#    Day-2 crea el secret TLS "custom-apps-cert" en openshift-ingress con el cert
#    y key del banco (fetcheados de BeyondTrust títulos: cert / key).
#
# ⚠️ NO crea un nuevo IngressController — modifica el DEFAULT que ROSA HCP crea.
#    ROSA propaga el cambio al IngressController vía la ROSA API (rhcs provider).
#
# WORKFLOW PARA HABILITAR (Day-1 iter.2):
#   1. Verificar que Day-2 Step B completó: oc get secret custom-apps-cert -n openshift-ingress
#   2. En terragrunt.hcl: enable_custom_ingress = true (ya trae hostname y secret_ref)
#   3. Correr orchestrator-cluster-config.yml con phase: terraform-only
#   4. Revisar PR → merge → CD aplica
#   5. Validar: oc get ingresscontroller default -n openshift-ingress-operator -o yaml
#                → spec.defaultCertificate.name = "custom-apps-cert"
#                → spec.domain = var.custom_routes_hostname
resource "rhcs_default_ingress" "custom" {
  count = var.enable_custom_ingress ? 1 : 0

  cluster = var.cluster_id

  # Hostname del dominio de banco para el router ROSA.
  # Routes creadas por el equipo de desarrollo con este hostname serán servidas
  # por el IngressController default con el cert del banco.
  # Formato: apps.<env>.aws.bancointernacional.ec (SIN el asterisco del wildcard).
  cluster_routes_hostname = var.custom_routes_hostname

  # Nombre del secret TLS en namespace openshift-ingress.
  # Creado por Day-2 Step B (workflow post-config, fetched from BeyondTrust).
  # ⚠️ El secret DEBE existir ANTES de hacer apply con este recurso habilitado.
  cluster_routes_tls_secret_ref = var.custom_routes_tls_secret_ref
}
