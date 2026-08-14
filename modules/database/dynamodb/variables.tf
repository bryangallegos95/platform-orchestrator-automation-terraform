# modules/database/dynamodb/variables.tf
#
# Inputs for the "Central Log" DynamoDB table set.
# DynamoDB is regional and VPC-less: no VPC/subnet/SG discovery variables here.
#
# Follows the platform three-tier hardening contract:
#   LOCKED     — SSE with account CMK (never AWS-managed key), PITR always on,
#                table set + key schema (defined in locals.tf, not overridable).
#   GUARD-RAIL — deletion protection floor per environment, TTL retention floor.
#   FREE       — billing mode + capacity, table class, GSI projection,
#                TTL attribute name / retention above the floor, extra tags.
#
# ⚠️ Este módulo se escribió SIN acceso a `platform-knowledge-base`.
#    Todo lo marcado `# TODO: validar contra platform-knowledge-base` es una
#    PROPUESTA (naming, alias KMS, pisos por ambiente) y debe confirmarse.

# ── Region ───────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region where the tables will be created."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 (primary) or us-east-2 (DR)."
  }
}

# ── Identity ──────────────────────────────────────────────────────────────────
variable "workload" {
  description = "Short name of THIS workload within the service (e.g. 'centrallog'). Used as name segment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workload))
    error_message = "workload must be lowercase alphanumeric and hyphens only."
  }
}

variable "funcionalidad" {
  description = "Propósito específico de este repo/recurso dentro del workload. Se usa en naming: {tipo}-aw-{region}-{workload}-{funcionalidad}-{tabla}-{ambiente}. Ejemplo: backingservices, trazabilidad."
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

# ── Billing / capacity ────────────────────────────────────────────────────────
variable "billing_mode" {
  description = <<-EOT
    Capacity mode for every table in the set.

    Default PAY_PER_REQUEST: sin datos de tráfico real de Central Log no es
    posible dimensionar RCU/WCU sin sobre/infra-provisionar. Cuando existan
    métricas reales se puede pasar a PROVISIONED + capacities.

    TODO: validar contra platform-knowledge-base (¿hay política FinOps que
    obligue a PROVISIONED en prod?).
  EOT
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "provisioned_read_capacity" {
  description = "RCU applied to every table and GSI when billing_mode = PROVISIONED. Ignored (must stay null) with PAY_PER_REQUEST."
  type        = number
  default     = null

  validation {
    condition     = var.provisioned_read_capacity == null ? true : var.provisioned_read_capacity >= 1
    error_message = "provisioned_read_capacity must be null or >= 1."
  }
}

variable "provisioned_write_capacity" {
  description = "WCU applied to every table and GSI when billing_mode = PROVISIONED. Ignored (must stay null) with PAY_PER_REQUEST."
  type        = number
  default     = null

  validation {
    condition     = var.provisioned_write_capacity == null ? true : var.provisioned_write_capacity >= 1
    error_message = "provisioned_write_capacity must be null or >= 1."
  }
}

variable "table_class" {
  description = "DynamoDB table class for every table in the set. STANDARD_INFREQUENT_ACCESS reduces storage cost (~60%) at a higher read/write cost — candidato FinOps para las tablas de payloads. TODO: validar contra platform-knowledge-base."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

# ── GSI ───────────────────────────────────────────────────────────────────────
variable "gsi_projection_type" {
  description = <<-EOT
    Projection applied to the GSIs of the `logs` table.
    ALL: las consultas por aplicación/servicio/estado/usuario devuelven el ítem
    completo sin fetch adicional a la tabla base, a costa de duplicar storage.

    TODO: validar contra platform-knowledge-base / patrón de acceso real de
    Central Log. Cambiar la proyección de un GSI existente obliga a recrearlo.
  EOT
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "KEYS_ONLY"], var.gsi_projection_type)
    error_message = "gsi_projection_type must be ALL or KEYS_ONLY (INCLUDE requires per-index non-key attribute lists, not modelled here)."
  }
}

# ── TTL ───────────────────────────────────────────────────────────────────────
variable "ttl_attribute_name" {
  description = "Item attribute holding the expiration epoch (seconds) used by DynamoDB TTL. Enabled on `logs` and `wait-logs`."
  type        = string
  default     = "ttl"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.ttl_attribute_name))
    error_message = "ttl_attribute_name must be alphanumeric/underscore."
  }
}

variable "ttl_retention_days" {
  description = <<-EOT
    Días de retención de logs antes de que TTL expire el ítem.
    null = piso por ambiente (ver locals.tf).

    NOTA: DynamoDB TTL NO acepta "días" — expira por epoch escrito en el
    atributo `ttl` por la aplicación. Este valor se expone como OUTPUT para que
    el productor (API / Lambda) calcule `now + ttl_retention_days`. El módulo
    solo habilita el mecanismo.

    TODO: validar contra platform-knowledge-base (política de retención de
    trazabilidad / requisitos regulatorios del banco).
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.ttl_retention_days == null ? true : (var.ttl_retention_days >= 1 && var.ttl_retention_days <= 3653)
    error_message = "ttl_retention_days must be null or between 1 and 3653 days."
  }
}

# ── Deletion protection ───────────────────────────────────────────────────────
variable "deletion_protection_enabled" {
  description = "Deletion protection. null = piso por ambiente (prod-like: true). Un repo hijo puede SUBIR el piso (activarlo en dev) pero nunca bajarlo en prod-like. TODO: validar contra platform-knowledge-base."
  type        = bool
  default     = null
}

# ── KMS ───────────────────────────────────────────────────────────────────────
variable "kms_alias" {
  description = "Alias of the account's pre-existing DynamoDB CMK, discovered at plan time. The module NEVER creates keys. TODO: validar contra platform-knowledge-base — alias real DESCONOCIDO, `alias/DynamoDB` es tentativo."
  type        = string
  default     = "alias/DynamoDB"

  validation {
    condition     = can(regex("^alias/", var.kms_alias))
    error_message = "kms_alias must start with 'alias/'."
  }
}

variable "kms_key_arn" {
  description = "Explicit KMS key ARN override. Empty string => discover by kms_alias."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a valid KMS key ARN."
  }
}

variable "kms_consumer_role_arns" {
  description = <<-EOT
    Map of IAM role ARNs that need KMS grants to read/write the encrypted tables.
    Keys are short labels for the grant name. Same pattern as
    aurora-postgresql/kms.tf and elasticache-serverless/kms.tf.

    Example:
      { "irsa-centrallog-api" = "arn:aws:iam::111122223333:role/irsa-aw-..." }
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
