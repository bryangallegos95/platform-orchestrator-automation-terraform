# modules/identity/irsa-role/variables.tf
#
# Inputs for IRSA (IAM Roles for Service Accounts) roles.
# Creates IAM roles with OIDC trust policies scoped to specific
# Kubernetes ServiceAccounts in ROSA HCP clusters.
#
# Follows the platform three-tier hardening contract:
#   LOCKED     — StringEquals trust (no wildcards), audience sts.amazonaws.com,
#                max session 3600s, /irsa/ path, SourceAccount condition.
#   GUARD-RAIL — max_session_duration ceiling (3600s), permission boundary opt-in.
#   FREE       — N roles via map, inline/managed policies, service accounts.

# ── Region ───────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 (primary) or us-east-2 (DR)."
  }
}

# ── Identity ──────────────────────────────────────────────────────────────────
variable "service" {
  description = "Short service/product name used in role naming."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service))
    error_message = "service must be lowercase alphanumeric and hyphens only."
  }
}

variable "workload" {
  description = "Short workload name (e.g. 'backing', 'core')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workload))
    error_message = "workload must be lowercase alphanumeric and hyphens only."
  }
}

variable "ambiente" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "preprod", "prod", "dr"], var.ambiente)
    error_message = "ambiente must be one of: dev, qa, preprod, prod, dr."
  }
}

variable "aws_account_id" {
  description = "Target AWS account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ── OIDC ──────────────────────────────────────────────────────────────────────
variable "oidc_issuer_url" {
  description = <<-EOT
    ROSA OIDC issuer URL (WITHOUT https:// prefix).
    Obtain from: terragrunt output -raw oidc_endpoint_url (rosa-negocio-{env}/)
    Example: "rh-oidc.s3.us-east-1.amazonaws.com/2raaaq28u2u1a86rtiu0662lnmrfm2jr"
  EOT
  type        = string

  validation {
    condition     = var.oidc_issuer_url != "" && !startswith(var.oidc_issuer_url, "https://")
    error_message = "oidc_issuer_url must not be empty and must NOT include the https:// prefix."
  }
}

# ── Roles ─────────────────────────────────────────────────────────────────────
variable "roles" {
  description = <<-EOT
    Map of IRSA roles to create. Each role has N service accounts and N policies.
    Keys become the role name suffix: irsa-aw-{region}-{service}-{workload}-{key}-{env}

    Example:
      {
        sqs-producer = {
          service_accounts = [
            { namespace = "bff-personas", name = "bff-sa" },
            { namespace = "bff-empresas", name = "bff-sa" },
          ]
          description = "SQS producer for all BFF microservices"
          inline_policies = {
            sqs-send = "{...json policy...}"
          }
        }
        sqs-consumer = {
          service_accounts = [
            { namespace = "notificaciones", name = "notif-sa" }
          ]
          managed_policy_arns = ["arn:aws:iam::aws:policy/..."]
        }
      }
  EOT
  type = map(object({
    service_accounts = list(object({
      namespace = string
      name      = string
    }))
    description             = optional(string, "")
    inline_policies         = optional(map(string), {})
    managed_policy_arns     = optional(list(string), [])
    permission_boundary_arn = optional(string, "")
    max_session_duration    = optional(number, 3600)
  }))

  validation {
    condition     = length(var.roles) > 0
    error_message = "At least one role must be defined."
  }

  validation {
    condition     = alltrue([for k, _ in var.roles : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Role keys must be lowercase alphanumeric and hyphens only."
  }

  validation {
    condition = alltrue([
      for k, v in var.roles : length(v.service_accounts) == 1
    ])
    error_message = "Each IRSA role must map to exactly one ServiceAccount (1:1 relationship). Create separate roles for separate service accounts."
  }

  validation {
    condition = alltrue([
      for k, v in var.roles : alltrue([
        for sa in v.service_accounts :
        can(regex("^[a-z0-9-]+$", sa.namespace)) && can(regex("^[a-z0-9-]+$", sa.name))
      ])
    ])
    error_message = "service_accounts namespace and name must be lowercase alphanumeric and hyphens."
  }

  validation {
    condition = alltrue([
      for k, v in var.roles : v.max_session_duration >= 900 && v.max_session_duration <= 3600
    ])
    error_message = "max_session_duration must be between 900 and 3600 (LOCKED ceiling: 1 hour)."
  }

  validation {
    condition = alltrue([
      for k, v in var.roles :
      v.permission_boundary_arn == "" || can(regex("^arn:aws:iam::", v.permission_boundary_arn))
    ])
    error_message = "permission_boundary_arn must be empty or a valid IAM policy ARN."
  }

  validation {
    condition = alltrue([
      for k, v in var.roles :
      length(v.inline_policies) > 0 || length(v.managed_policy_arns) > 0
    ])
    error_message = "Every role must have at least one inline_policy or managed_policy_arn."
  }
}

# ── Mandatory tags ────────────────────────────────────────────────────────────
variable "aplicacion" {
  description = "Application name (mandatory corporate tag)."
  type        = string

  validation {
    condition     = length(var.aplicacion) >= 3 && !contains(["XXXX", "TBD", "CHANGEME", "TODO"], upper(var.aplicacion))
    error_message = "aplicacion must be at least 3 chars and not a placeholder."
  }
}

variable "propietario_recurso" {
  description = "Resource owner (mandatory corporate tag)."
  type        = string

  validation {
    condition     = length(var.propietario_recurso) >= 3 && !contains(["XXXX", "TBD", "CHANGEME", "TODO"], upper(var.propietario_recurso))
    error_message = "propietario_recurso must be at least 3 chars and not a placeholder."
  }
}

variable "producto" {
  description = "Product name (mandatory corporate tag)."
  type        = string

  validation {
    condition     = length(var.producto) >= 3 && !contains(["XXXX", "TBD", "CHANGEME", "TODO"], upper(var.producto))
    error_message = "producto must be at least 3 chars and not a placeholder."
  }
}

variable "centro_costo" {
  description = "Cost center (mandatory corporate tag)."
  type        = string

  validation {
    condition     = length(var.centro_costo) >= 3 && !contains(["XXXX", "TBD", "CHANGEME", "TODO"], upper(var.centro_costo))
    error_message = "centro_costo must be at least 3 chars and not a placeholder."
  }
}

variable "extra_tags" {
  description = "Additional tags to merge with the mandatory set."
  type        = map(string)
  default     = {}
}
