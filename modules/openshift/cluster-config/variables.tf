# modules/openshift/cluster-config/variables.tf

# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_id" {
  description = "ROSA HCP cluster ID (from OCM / rosa describe cluster). Hardcoded post-Day-0 in terragrunt.hcl."
  type        = string
}

variable "cluster_name" {
  description = "Canonical cluster name (int-dev, int-qa, neg-dev, etc.). Used for logging only."
  type        = string
}

# ── htpasswd IDP ──────────────────────────────────────────────────────────────

variable "enable_htpasswd" {
  description = "Enable htpasswd IDP (local admin user). MUST be false for prod and dr."
  type        = bool
  default     = false

  validation {
    condition     = !(var.enable_htpasswd && can(regex("^(prod|dr)$", var.cluster_name)))
    error_message = "enable_htpasswd MUST be false for prod and dr clusters. Regulatory requirement (SB-2023-01901)."
  }
}

variable "htpasswd_username" {
  description = "htpasswd local admin username. Must match the username in BeyondTrust Credential 'admin_user'."
  type        = string
  default     = "admin"
}

variable "htpasswd_password" {
  description = "htpasswd admin password. SENSITIVE — injected via TF_VAR_htpasswd_password from BeyondTrust (title: admin_user → .Password)."
  type        = string
  sensitive   = true
  default     = ""
}

# ── EntraID openid IDP ────────────────────────────────────────────────────────

variable "entra_client_id" {
  description = "Azure Application (client) ID. Non-sensitive. Fetched from BeyondTrust title: app_id (via extra_vars)."
  type        = string
}

variable "entra_client_secret" {
  description = "Azure client secret. SENSITIVE — injected via TF_VAR_entra_client_secret from BeyondTrust (title: client-secret)."
  type        = string
  sensitive   = true
}

variable "entra_tenant_id" {
  description = "Azure AD tenant UUID. Non-sensitive. Fetched from BeyondTrust title: tenant-id (via extra_vars)."
  type        = string
}

# ── Custom Ingress (Day-1 iter.2) ─────────────────────────────────────────────

variable "enable_custom_ingress" {
  description = <<-EOT
    Enable rhcs_default_ingress custom hostname + TLS cert configuration.
    MUST be false until Day-2 Step B has created the TLS secret 'custom-apps-cert'
    in the openshift-ingress namespace. Set to true for Day-1 iter.2 run.
  EOT
  type    = bool
  default = false
}

variable "custom_routes_hostname" {
  description = <<-EOT
    Custom apps hostname for the ROSA default IngressController.
    Format: apps.<env>.aws.bancointernacional.ec (WITHOUT wildcard asterisk).
    Example: apps.dev.aws.bancointernacional.ec
    Only used when enable_custom_ingress = true.
  EOT
  type    = string
  default = ""

  validation {
    condition     = !var.enable_custom_ingress || length(var.custom_routes_hostname) > 0
    error_message = "custom_routes_hostname is required when enable_custom_ingress = true."
  }
}

variable "custom_routes_tls_secret_ref" {
  description = <<-EOT
    Name of the TLS secret in openshift-ingress namespace that contains the bank's
    wildcard certificate. Created by Day-2 Step B (fetched from BeyondTrust titles: cert / key).
    Must exist BEFORE applying with enable_custom_ingress = true.
    Standard name: custom-apps-cert (consistent across all environments).
  EOT
  type    = string
  default = "custom-apps-cert"
}
