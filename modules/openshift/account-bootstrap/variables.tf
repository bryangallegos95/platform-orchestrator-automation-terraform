# modules/openshift/account-bootstrap/variables.tf
#
# Shared ROSA HCP account roles (Installer/Support/Worker). One set per account.

variable "aws_region" {
  description = "AWS region. us-east-1 (primary) or us-east-2 (DR)."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 or us-east-2."
  }
}

variable "account_role_prefix" {
  description = "Prefix for the SHARED ROSA HCP account roles. E.g. 'bin-rosa-hcp'."
  type        = string
  default     = "bin-rosa-hcp"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.account_role_prefix))
    error_message = "account_role_prefix must be lowercase alphanumeric and hyphens."
  }
}

# ── Mandatory tags (org contract — all four required, no defaults) ────────────
variable "aplicacion" {
  description = "[MANDATORY TAG] Application that owns this resource."
  type        = string
  validation {
    condition     = length(trimspace(var.aplicacion)) > 0
    error_message = "aplicacion (mandatory tag) must not be empty."
  }
}

variable "centro_costo" {
  description = "[MANDATORY TAG] Cost center code for billing allocation."
  type        = string
  validation {
    condition     = length(trimspace(var.centro_costo)) > 0
    error_message = "centro_costo (mandatory tag) must not be empty."
  }
}

variable "producto" {
  description = "[MANDATORY TAG] Product / business unit."
  type        = string
  validation {
    condition     = length(trimspace(var.producto)) > 0
    error_message = "producto (mandatory tag) must not be empty."
  }
}

variable "propietario_recurso" {
  description = "[MANDATORY TAG] Resource owner (team or person)."
  type        = string
  validation {
    condition     = length(trimspace(var.propietario_recurso)) > 0
    error_message = "propietario_recurso (mandatory tag) must not be empty."
  }
}

variable "extra_tags" {
  description = "Optional additional tags merged after the mandatory four."
  type        = map(string)
  default     = {}
}
