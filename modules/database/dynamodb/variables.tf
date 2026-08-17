# modules/database/dynamodb/variables.tf
#
# Inputs for the Central Log DynamoDB tier (5 tables) deployed into an existing
# AWS account. The CMK is DISCOVERED by alias — no key IDs passed in, no shared
# state. Mandatory tags are enforced at the variable level.
#
# Three-tier hardening contract:
#   LOCKED     — CMK encryption, the 5-table catalog, key schema, Streams on
#                logs/applications/services, prevent_destroy on logs.
#                NOT exposed as variables (AGENTS.md: "Add variables for LOCKED
#                settings" is on the Do-NOT list).
#   GUARD-RAIL — deletion protection, PITR, TTL retention window, Auto Scaling
#                capacity ceiling. A son repo may RAISE the floor, never lower it.
#   FREE       — billing_mode, capacities, TTL attribute name, tags.

# ── Region ───────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region where the tables will be created."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 (primary) or us-east-2 (DR). No other regions are enabled."
  }
}

# ── Identity ──────────────────────────────────────────────────────────────────
variable "name_prefix" {
  description = <<-EOT
    Prefix for every table name: "{name_prefix}-logs", "{name_prefix}-log-payloads",
    "{name_prefix}-applications", "{name_prefix}-services", "{name_prefix}-wait-logs".

    This is the naming pattern already running in the validated Central Log
    reference implementation (CL-LLD-DAT-01 §10.1). It has NOT yet been contrasted
    against the corporate convention {tipo}-aw-{region}-{funcion}-{ambiente}
    enforced by scripts/naming_pattern_validator.sh — see the README.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,48}$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric plus hyphens, start with a letter or digit, and be 2-49 chars."
  }
}

variable "ambiente" {
  description = "Environment name. Drives every guard-rail floor in this module."
  type        = string

  validation {
    condition     = contains(["dev", "test", "uat", "prod"], var.ambiente)
    error_message = "ambiente must be one of: dev, test, uat, prod."
  }
}

variable "aws_account_id" {
  description = "Target AWS account ID — provided by the workflow. Tables and the discovered CMK MUST live in this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "workload" {
  description = "Short name of THIS workload within the service (e.g. 'centrallog'). Not used in table naming while naming derives from name_prefix; declared for interface consistency with the other platform modules and for the pending naming contrast."
  type        = string
  default     = ""

  validation {
    condition     = var.workload == "" || can(regex("^[a-z0-9-]+$", var.workload))
    error_message = "workload must be empty or lowercase alphanumeric and hyphens only."
  }
}

variable "funcionalidad" {
  description = "Propósito específico de este repo/recurso dentro del workload. Reservado para la convención corporativa {tipo}-aw-{region}-{workload}-{funcionalidad}-{ambiente}; hoy el naming lo aporta name_prefix."
  type        = string
  default     = ""

  validation {
    condition     = var.funcionalidad == "" || can(regex("^[a-z0-9-]+$", var.funcionalidad))
    error_message = "funcionalidad must be empty or lowercase alphanumeric and hyphens only."
  }
}

# ── KMS (LOCKED: always a CMK — only WHICH key is configurable) ───────────────
variable "kms_key_alias" {
  description = "Alias of the account's pre-existing DynamoDB CMK, discovered at plan time. The module NEVER creates keys. Canonical account baseline alias is 'alias/DynamoDB' (case-sensitive) — confirm against the account baseline before the first apply."
  type        = string
  default     = "alias/DynamoDB"

  validation {
    condition     = can(regex("^alias/", var.kms_key_alias))
    error_message = "kms_key_alias must start with 'alias/'."
  }
}

variable "kms_key_arn" {
  description = "Explicit KMS key ARN override. Empty string => discover by kms_key_alias. An AWS-managed key is never acceptable (CL-LLD-DAT-01 §9.1)."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a valid KMS key ARN."
  }
}

# ── Billing mode and capacity (FREE, within the guard-railed ceiling) ─────────
#
# Criterion fixed by CL-LLD-DAT-01 §8.2: PAY_PER_REQUEST in the low environments,
# where volume is sporadic, and PROVISIONED + Auto Scaling in production, where
# the load is sustained and predictable. At 10M records/day the saving over
# On-Demand is around 78%.
#
# Only the two high-volume tables (logs, log-payloads) honour this variable. The
# catalog tables and wait-logs are always PAY_PER_REQUEST: tens of items each,
# where provisioning capacity would cost more than it saves (§5.4, §5.5).
variable "billing_mode" {
  description = "Billing mode of the high-volume tables (logs, log-payloads). PROVISIONED also activates Auto Scaling on the logs table."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Baseline RCUs when billing_mode = PROVISIONED. Also the Auto Scaling minimum on the logs table."
  type        = number
  default     = 25

  validation {
    condition     = var.read_capacity >= 1
    error_message = "read_capacity must be at least 1."
  }
}

variable "write_capacity" {
  description = "Baseline WCUs when billing_mode = PROVISIONED. Also the Auto Scaling minimum on the logs table. CL-LLD-DAT-01 §8.2 sizes production at ~180 WCU sustained for 10M records/day."
  type        = number
  default     = 25

  validation {
    condition     = var.write_capacity >= 1
    error_message = "write_capacity must be at least 1."
  }
}

variable "read_capacity_max" {
  description = "Ceiling Auto Scaling may provision for reads. Clamped to the per-environment ceiling (see locals.tf)."
  type        = number
  default     = 500

  validation {
    condition     = var.read_capacity_max >= 1
    error_message = "read_capacity_max must be at least 1."
  }
}

variable "write_capacity_max" {
  description = "Ceiling Auto Scaling may provision for writes. Clamped to the per-environment ceiling (see locals.tf)."
  type        = number
  default     = 1500

  validation {
    condition     = var.write_capacity_max >= 1
    error_message = "write_capacity_max must be at least 1."
  }
}

variable "autoscaling_target_utilization" {
  description = "Target utilisation of the provisioned capacity, in percent. CL-LLD-DAT-01 §8.2 sizes the platform at 70%."
  type        = number
  default     = 70

  validation {
    condition     = var.autoscaling_target_utilization >= 20 && var.autoscaling_target_utilization <= 90
    error_message = "autoscaling_target_utilization must be between 20 and 90."
  }
}

# ── Protective controls (GUARD-RAIL) ─────────────────────────────────────────
variable "deletion_protection" {
  description = "Protects the tables from accidental deletion. null => module default (ON everywhere). uat/prod force it ON and a son repo cannot disable it."
  type        = bool
  default     = null
}

variable "point_in_time_recovery" {
  description = "Continuous backup (PITR, 35 days). null => module default (ON everywhere). uat/prod force it ON — CL-LLD-DAT-01 §9.3 requires PITR on every table."
  type        = bool
  default     = null
}

# ── TTL (GUARD-RAIL: window / FREE: attribute name) ──────────────────────────
#
# TODO: decisión de negocio pendiente — CL-LLD-DAT-01 §12.2 #4.
# Hot retention window: 30 or 90 days. The difference is ~USD 123/month
# (~247 GB vs ~740 GB accumulated). §8.3 recommends starting at 30 days and
# sizing the window by the typical age of an investigation, not by query volume.
# Negocio + Operaciones must confirm before the window is treated as final.
#
# NOTE ON WHAT TERRAFORM ACTUALLY CONTROLS: a DynamoDB TTL configuration only
# names the attribute that carries the expiry epoch. The retention WINDOW lives
# in whatever writes that attribute — the ingest Lambda computes exp = now +
# retention. This variable is therefore published as an output for the
# application layer to consume; it does not by itself delete anything.
variable "ttl_retention_days" {
  description = "Hot retention window in days, published for the writer that computes the TTL attribute. Raised to the per-environment floor when set lower. DECISIÓN DE NEGOCIO PENDIENTE: 30 (default, cheaper) vs 90 — CL-LLD-DAT-01 §12.2 #4."
  type        = number
  default     = 30

  validation {
    condition     = var.ttl_retention_days >= 1 && var.ttl_retention_days <= 3650
    error_message = "ttl_retention_days must be between 1 and 3650."
  }
}

variable "ttl_attribute_name" {
  description = "Name of the TTL attribute on logs, log-payloads and wait-logs. Platform default 'exp' (CL-LLD-DAT-01 §7.2, renamed from the earlier 'expires_at'). Override only if the application contract diverges."
  type        = string
  default     = "exp"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,254}$", var.ttl_attribute_name))
    error_message = "ttl_attribute_name must start with a letter and contain only letters, digits and underscores."
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
