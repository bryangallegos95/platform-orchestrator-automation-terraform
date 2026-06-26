# modules/openshift/cluster-config/variables.tf

# ── Cluster identity ──────────────────────────────────────────────────────────
variable "cluster_id" {
  description = "ROSA HCP cluster ID (output of the rosa-hcp module). Used to bind IDPs to the cluster via OCM."
  type        = string

  validation {
    condition     = length(trimspace(var.cluster_id)) > 0
    error_message = "cluster_id must not be empty. Get it from: terragrunt output -raw cluster_id (rosa-hcp unit)."
  }
}

variable "cluster_name" {
  description = "Cluster name (e.g. int-dev). Used only for tagging/documentation context."
  type        = string
}

# ── htpasswd IDP (non-prod gate) ─────────────────────────────────────────────
variable "enable_htpasswd" {
  description = <<-EOT
    Enable the htpasswd local IDP. MUST be false on prod and dr.
    Used exclusively for Day-2 bootstrapping (oc login) on non-prod clusters.
    Set to true  → dev, qa, preprod.
    Set to false → prod, dr  (enforced by terragrunt invocation; no default here).
  EOT
  type        = bool

  validation {
    condition     = var.enable_htpasswd == true || var.enable_htpasswd == false
    error_message = "enable_htpasswd must be an explicit boolean (true or false). Never omit it."
  }
}

variable "htpasswd_username" {
  description = "Username for the htpasswd local admin (default: admin). Only used when enable_htpasswd = true."
  type        = string
  default     = "admin"
}

variable "htpasswd_password" {
  description = <<-EOT
    Password for the htpasswd local admin. Passed via TF_VAR_htpasswd_password
    (GitHub Secret) — never hardcoded in terragrunt.hcl.
    Only used when enable_htpasswd = true.
    Minimum: 14 chars, must contain upper, lower, digit, special char (ROSA policy).
  EOT
  type      = string
  sensitive = true
  default   = null   # null-safe: resource has count=0 when enable_htpasswd=false

  validation {
    condition     = var.enable_htpasswd == false || (var.htpasswd_password != null && length(var.htpasswd_password) >= 14)
    error_message = "htpasswd_password is required when enable_htpasswd = true and must be >= 14 characters."
  }
}

# ── EntraID openid IDP ────────────────────────────────────────────────────────
variable "entra_client_id" {
  description = <<-EOT
    Azure AD App Registration client ID. Non-sensitive — identifies the app,
    does not grant access alone. Passed via TF_VAR_entra_client_id (GitHub Secret)
    to avoid committing to Git even though it is not confidential.
  EOT
  type = string

  validation {
    condition     = length(trimspace(var.entra_client_id)) > 0
    error_message = "entra_client_id must not be empty."
  }
}

variable "entra_client_secret" {
  description = <<-EOT
    Azure AD App Registration client secret. SENSITIVE — persisted in Terraform
    state encrypted with the cluster KMS key (accepted by Seguridad).
    Passed via TF_VAR_entra_client_secret (GitHub Secret).
    Never set a default; never commit a value.
  EOT
  type      = string
  sensitive = true

  validation {
    condition     = length(trimspace(var.entra_client_secret)) > 0
    error_message = "entra_client_secret must not be empty."
  }
}

variable "entra_tenant_id" {
  description = <<-EOT
    Azure AD tenant ID. Used to construct the issuer URL:
    https://login.microsoftonline.com/<tenant_id>/v2.0
    Passed via TF_VAR_entra_tenant_id (GitHub Secret).
  EOT
  type = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.entra_tenant_id))
    error_message = "entra_tenant_id must be a valid UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)."
  }
}
