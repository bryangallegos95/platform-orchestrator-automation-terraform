# modules/messaging/sqs/variables.tf
#
# Inputs for SQS queues deployed into an existing AWS account.
# Follows the platform three-tier hardening contract:
#   LOCKED     — encryption (CMK), deny non-TLS, DLQ always created
#   GUARD-RAIL — retention floors, max_receive_count floors
#   FREE       — visibility timeout, delay, FIFO, deduplication, message size

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
  description = "Short service/product name (DEPRECATED — no longer used in resource naming). Kept for backward compatibility with existing son-repo invocations."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service))
    error_message = "service must be lowercase alphanumeric and hyphens only."
  }
}

variable "vpc_discovery_service" {
  description = "Service name used to discover the Spoke VPC by Name tag. SQS does not perform VPC discovery itself, but this variable is provided for interface consistency with other platform modules (aurora-postgresql, elasticache-serverless)."
  type        = string
  default     = ""

  validation {
    condition     = var.vpc_discovery_service == "" || can(regex("^[a-z0-9-]+$", var.vpc_discovery_service))
    error_message = "vpc_discovery_service must be empty or lowercase alphanumeric and hyphens only."
  }
}

variable "workload" {
  description = "Short name of THIS workload within the service (e.g. 'core', 'backing'). Used as name suffix."
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
  description = "Target AWS account ID — provided by workflow. Used for queue policy scoping and guards."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ── KMS ───────────────────────────────────────────────────────────────────────
variable "kms_key_alias" {
  description = "Alias of the account's pre-existing SQS CMK, discovered at plan time. The module NEVER creates keys."
  type        = string
  default     = "alias/SQS"

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

variable "kms_data_key_reuse_period_seconds" {
  description = "Duration (seconds) SQS reuses a data encryption key before calling KMS again. Range: 60-86400."
  type        = number
  default     = 300

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "kms_data_key_reuse_period_seconds must be between 60 and 86400."
  }
}

# ── Queues ────────────────────────────────────────────────────────────────────
variable "queues" {
  description = <<-EOT
    Map of SQS queues to create. Each queue gets a mandatory DLQ.
    Keys become part of the queue name: sqs-aw-{region}-{service}-{workload}-{key}-{env}

    Example:
      {
        notificaciones = {
          fifo                       = false
          visibility_timeout_seconds = 30
          message_retention_days     = 7
        }
        pagos = {
          fifo                        = true
          content_based_deduplication = true
          message_retention_days      = 14
        }
      }
  EOT
  type = map(object({
    fifo                        = optional(bool, false)
    visibility_timeout_seconds  = optional(number, 30)
    message_retention_days      = optional(number, 4)
    max_message_size_bytes      = optional(number, 262144)
    delay_seconds               = optional(number, 0)
    receive_wait_time_seconds   = optional(number, 20)
    content_based_deduplication = optional(bool, false)
    # DLQ configuration
    dlq_max_receive_count      = optional(number, 3)
    dlq_message_retention_days = optional(number, 14)
  }))

  validation {
    condition     = length(var.queues) > 0
    error_message = "At least one queue must be defined."
  }

  validation {
    condition     = alltrue([for k, _ in var.queues : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Queue keys must be lowercase alphanumeric and hyphens only."
  }

  validation {
    condition     = alltrue([for k, v in var.queues : v.visibility_timeout_seconds >= 0 && v.visibility_timeout_seconds <= 43200])
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }

  validation {
    condition     = alltrue([for k, v in var.queues : v.message_retention_days >= 1 && v.message_retention_days <= 14])
    error_message = "message_retention_days must be between 1 and 14."
  }

  validation {
    condition     = alltrue([for k, v in var.queues : v.max_message_size_bytes >= 1024 && v.max_message_size_bytes <= 262144])
    error_message = "max_message_size_bytes must be between 1024 and 262144."
  }

  validation {
    condition     = alltrue([for k, v in var.queues : v.delay_seconds >= 0 && v.delay_seconds <= 900])
    error_message = "delay_seconds must be between 0 and 900."
  }

  validation {
    condition     = alltrue([for k, v in var.queues : v.receive_wait_time_seconds >= 0 && v.receive_wait_time_seconds <= 20])
    error_message = "receive_wait_time_seconds must be between 0 and 20."
  }

  validation {
    condition     = alltrue([for k, v in var.queues : v.dlq_max_receive_count >= 1 && v.dlq_max_receive_count <= 1000])
    error_message = "dlq_max_receive_count must be between 1 and 1000."
  }

  validation {
    condition     = alltrue([for k, v in var.queues : v.dlq_message_retention_days >= 1 && v.dlq_message_retention_days <= 14])
    error_message = "dlq_message_retention_days must be between 1 and 14."
  }
}

# ── KMS Consumer Roles ────────────────────────────────────────────────────────
variable "kms_consumer_role_arns" {
  description = <<-EOT
    Map of IAM role ARNs that need KMS grants to encrypt/decrypt SQS messages.
    Keys are short labels for the grant name.

    Example:
      { "irsa-sqs-producer" = "arn:aws:iam::111122223333:role/irsa-aw-..." }
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, arn in var.kms_consumer_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/", arn))])
    error_message = "Every kms_consumer_role_arns value must be an IAM role ARN."
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
