# modules/database/elasticache-serverless/variables.tf
#
# Inputs for an ElastiCache Serverless cache deployed into an existing Spoke VPC.
# VPC and subnets are DISCOVERED by the tag/naming contract — no IDs passed in.
#
# Follows the platform three-tier hardening contract:
#   LOCKED     — TLS in-transit (forced by serverless), CMK at-rest, VPC-only,
#                IAM auth, no public access, SG deny-all inbound by default.
#   GUARD-RAIL — snapshot retention floor, ECPU/storage ceilings per environment.
#   FREE       — engine (valkey/redis), major version, usage limits within ceiling,
#                daily snapshot time, extra tags, parameters.

# ── Region ───────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 (primary) or us-east-2 (DR)."
  }
}

# ── Identity ──────────────────────────────────────────────────────────────────
variable "service" {
  description = "OU name (lowercase) used for VPC discovery via tag 'ou'. Passed from orchestrator extra_vars. Example: contenerizacion, datosanalitica, plataforma."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service))
    error_message = "service must be lowercase alphanumeric and hyphens only."
  }
}

variable "vpc_discovery_service" {
  description = "DEPRECATED — VPC discovery now uses tag 'ou' from var.service. This variable is ignored."
  type        = string
  default     = ""

  validation {
    condition     = var.vpc_discovery_service == "" || can(regex("^[a-z0-9-]+$", var.vpc_discovery_service))
    error_message = "vpc_discovery_service must be empty or lowercase alphanumeric and hyphens only."
  }
}

variable "workload" {
  description = "Short name of THIS cache workload within the service (e.g. 'sessions', 'cache', 'rate-limit'). Used as name suffix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workload))
    error_message = "workload must be lowercase alphanumeric and hyphens only."
  }
}

variable "funcionalidad" {
  description = "Propósito específico de este repo/recurso dentro del workload. Se usa en naming: {tipo}-aw-{region}-{workload}-{funcionalidad}-{ambiente}. Ejemplo: backingservices, consultasclientes, onboarding"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.funcionalidad))
    error_message = "funcionalidad must be lowercase alphanumeric and hyphens only."
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
  description = "Target AWS account ID — provided by workflow. Used for guards and KMS grants."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ── Engine ────────────────────────────────────────────────────────────────────
variable "engine" {
  description = "Cache engine: 'valkey' (recommended — 33% lower cost, Apache 2.0) or 'redis'."
  type        = string
  default     = "valkey"

  validation {
    condition     = contains(["valkey", "redis"], var.engine)
    error_message = "engine must be 'valkey' or 'redis'."
  }
}

variable "major_engine_version" {
  description = "Major engine version. Valkey: '8' (latest). Redis OSS: '7'."
  type        = string
  default     = "8"

  validation {
    condition     = can(regex("^[0-9]+$", var.major_engine_version))
    error_message = "major_engine_version must be a number string (e.g. '7', '8')."
  }
}

# ── Usage Limits (FinOps guard-rails) ─────────────────────────────────────────
variable "max_ecpu_per_second" {
  description = "Maximum ElastiCache Processing Units (ECPU) per second. null = auto ceiling per environment."
  type        = number
  default     = null

  validation {
    condition     = var.max_ecpu_per_second == null || var.max_ecpu_per_second >= 1000
    error_message = "max_ecpu_per_second must be null or >= 1000."
  }
}

variable "max_data_storage_gb" {
  description = "Maximum data storage in GB. null = auto ceiling per environment."
  type        = number
  default     = null

  validation {
    condition     = var.max_data_storage_gb == null || var.max_data_storage_gb >= 1
    error_message = "max_data_storage_gb must be null or >= 1."
  }
}

# ── Snapshots ─────────────────────────────────────────────────────────────────
variable "snapshot_retention_days" {
  description = "Number of days to retain automatic snapshots. null = auto floor per environment (prod/dr: 7, dev/qa: 1)."
  type        = number
  default     = null

  validation {
    condition     = var.snapshot_retention_days == null || (var.snapshot_retention_days >= 0 && var.snapshot_retention_days <= 35)
    error_message = "snapshot_retention_days must be null or between 0 and 35."
  }
}

variable "daily_snapshot_time" {
  description = "UTC time for daily snapshot (HH:MM format). null = AWS default."
  type        = string
  default     = null

  validation {
    condition     = var.daily_snapshot_time == null || can(regex("^[0-2][0-9]:[0-5][0-9]$", var.daily_snapshot_time))
    error_message = "daily_snapshot_time must be null or HH:MM format."
  }
}

# ── KMS ───────────────────────────────────────────────────────────────────────
variable "kms_key_alias" {
  description = "Alias of the account's pre-existing ElastiCache CMK, discovered at plan time. The module NEVER creates keys."
  type        = string
  default     = "alias/ElastiCache"

  validation {
    condition     = can(regex("^alias/", var.kms_key_alias))
    error_message = "kms_key_alias must start with 'alias/'."
  }
}

variable "kms_key_arn" {
  description = "Explicit KMS key ARN override. Empty string => discover by kms_key_alias."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a valid KMS key ARN."
  }
}

variable "kms_consumer_role_arns" {
  description = <<-EOT
    Map of IAM role ARNs that need KMS grants for ElastiCache encryption.
    Keys are short labels for the grant name.

    Example:
      { "irsa-redis-connect" = "arn:aws:iam::111122223333:role/irsa-aw-..." }
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, arn in var.kms_consumer_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/", arn))])
    error_message = "Every kms_consumer_role_arns value must be an IAM role ARN."
  }
}

# ── Network access ────────────────────────────────────────────────────────────
variable "allowed_security_group_ids" {
  description = "Consumer Security Group IDs granted cache port access (6379+6380). Default [] = no inbound."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.allowed_security_group_ids : can(regex("^sg-", id))])
    error_message = "Every allowed_security_group_ids entry must be a Security Group ID (sg-...)."
  }
}

variable "allowed_cidrs" {
  description = <<-EOT
    CIDR blocks granted cache port access (6379+6380). Default [] = no inbound.
    Prefer Security Group IDs over CIDRs (identity-based > network-based).

    Example:
      [{ description = "App tier subnets", cidr = "10.10.0.0/24" }]
  EOT
  type = list(object({
    description = string
    cidr        = string
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.allowed_cidrs : can(cidrnetmask(r.cidr))])
    error_message = "Every allowed_cidrs[].cidr must be a valid CIDR block."
  }
}

# ── User Group (IAM auth for Serverless) ──────────────────────────────────────
variable "user_group_id" {
  description = "ElastiCache user group ID for IAM-based authentication. Empty string = no user group (default IAM auth only)."
  type        = string
  default     = ""
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
