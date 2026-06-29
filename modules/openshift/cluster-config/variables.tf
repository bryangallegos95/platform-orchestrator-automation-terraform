# modules/openshift/cluster-config/variables.tf

# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_id" {
  description = "ROSA HCP cluster ID (from OCM / rosa describe cluster). Hardcoded post-Day-0 in terragrunt.hcl."
  type        = string
}

variable "cluster_name" {
  description = "Canonical cluster name (int-dev, int-qa, neg-dev, etc.). Used for logging + validation only."
  type        = string
}

# ── htpasswd IDP ──────────────────────────────────────────────────────────────

variable "enable_htpasswd" {
  description = "Enable htpasswd IDP (local admin user). MUST be false for prod and dr."
  type        = bool
  default     = false

  validation {
    condition     = !(var.enable_htpasswd && can(regex("(prod|dr)$", var.cluster_name)))
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

# ── Custom Ingress: REMOVED ───────────────────────────────────────────────────
# The variables enable_custom_ingress / custom_routes_hostname /
# custom_routes_tls_secret_ref were removed. The bank-domain ingress is now a
# SECONDARY IngressController managed by GitOps (iac-gitops-platform-baseline/
# base/ingress/), not by this Terraform module. See main.tf header.
