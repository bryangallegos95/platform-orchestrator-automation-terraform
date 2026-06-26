# modules/openshift/cluster-config/variables.tf
#
# Todas las variables sensibles llegan vía TF_VAR_* inyectados por ci.yml
# desde BeyondTrust Secrets Safe. NUNCA se hardcodean en terragrunt.hcl.

# ── Cluster identity ──────────────────────────────────────────────────────────
variable "cluster_id" {
  description = <<-EOT
    ROSA HCP cluster ID (output del módulo rosa-hcp).
    Usado para vincular los IDPs al cluster vía OCM.
    Obtener con: terragrunt output -raw cluster_id (unidad rosa-hcp).
  EOT
  type = string

  validation {
    condition     = length(trimspace(var.cluster_id)) > 0
    error_message = "cluster_id no debe estar vacío."
  }
}

variable "cluster_name" {
  description = "Nombre del cluster (ej. int-dev). Solo para documentación/tagging."
  type        = string
}

# ── htpasswd IDP (gate non-prod) ──────────────────────────────────────────────
variable "enable_htpasswd" {
  description = <<-EOT
    Habilita el IDP htpasswd local. DEBE ser false en prod y dr.
    Uso exclusivo: bootstrap Day-2 (oc login admin/changeme en no-prod).
      true  → dev, qa, preprod
      false → prod, dr  (enforced por el terragrunt.hcl de cada ambiente)
  EOT
  type = bool

  validation {
    condition     = var.enable_htpasswd == true || var.enable_htpasswd == false
    error_message = "enable_htpasswd debe ser un booleano explícito (true o false)."
  }
}

variable "htpasswd_username" {
  description = "Username del admin local htpasswd. Solo cuando enable_htpasswd = true."
  type        = string
  default     = "admin"
}

variable "htpasswd_password" {
  description = <<-EOT
    Password del admin local htpasswd.
    Origen: BeyondTrust Secrets Safe (title: htpasswd-password)
            → inyectado por ci.yml como TF_VAR_htpasswd_password
            → nunca hardcodeado en terragrunt.hcl
    Solo se usa cuando enable_htpasswd = true.
    Mínimo 14 chars (política ROSA).
  EOT
  type      = string
  sensitive = true
  default   = null   # null-safe: el recurso tiene count=0 cuando enable_htpasswd=false

  validation {
    condition     = var.enable_htpasswd == false || (var.htpasswd_password != null && length(var.htpasswd_password) >= 14)
    error_message = "htpasswd_password es requerido cuando enable_htpasswd = true y debe tener >= 14 caracteres."
  }
}

# ── EntraID openid IDP ────────────────────────────────────────────────────────
variable "entra_client_id" {
  description = <<-EOT
    Application (client) ID del App Registration de Azure AD.
    Técnicamente no-sensible (solo identifica la app, no autentica por sí solo).
    Origen: BeyondTrust Secrets Safe (title: app_id)
            → recuperado en prepare step del orquestador
            → pasado via extra_vars como TF_VAR_entra_client_id
    Aparece en el PR body table (aceptable — es un identificador público).
  EOT
  type = string

  validation {
    condition     = length(trimspace(var.entra_client_id)) > 0
    error_message = "entra_client_id no debe estar vacío."
  }
}

variable "entra_client_secret" {
  description = <<-EOT
    Client secret del App Registration de Azure AD. SENSIBLE.
    Persiste en Terraform state cifrado con AES-256 en S3 (aceptado por Seguridad).
    Origen: BeyondTrust Secrets Safe (title: client-secret)
            → inyectado por ci.yml como TF_VAR_entra_client_secret (masked)
            → nunca aparece en PR body, logs, ni plan output en texto plano
    Nunca setear un default. Nunca commitear un valor.
  EOT
  type      = string
  sensitive = true

  validation {
    condition     = length(trimspace(var.entra_client_secret)) > 0
    error_message = "entra_client_secret no debe estar vacío."
  }
}

variable "entra_tenant_id" {
  description = <<-EOT
    Tenant UUID de Azure AD.
    Usado para construir el issuer URL:
      https://login.microsoftonline.com/<tenant_id>/v2.0
    Técnicamente no-sensible (es público en Azure).
    Origen: BeyondTrust Secrets Safe (title: tenant-id)
            → recuperado en prepare step del orquestador
            → pasado via extra_vars como TF_VAR_entra_tenant_id
  EOT
  type = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.entra_tenant_id))
    error_message = "entra_tenant_id debe ser un UUID válido (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)."
  }
}
