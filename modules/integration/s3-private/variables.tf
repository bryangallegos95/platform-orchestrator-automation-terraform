# modules/integration/s3-private/variables.tf
#
# All inputs for the Private S3 Bucket module.
# Implements the Banco Internacional S3 Security Baseline (CIS AWS v5.0.0).
#
# Security controls enforced by this module:
#   1.1  Separación por entorno      → bucket per environment (naming convention)
#   2.1  ACLs deshabilitadas         → BucketOwnerEnforced
#   2.2  Restricción de acceso       → bucket policy: mínimo privilegio
#   2.3  Acceso público bloqueado    → Block Public Access (4 flags)
#   3.1  Versionado                  → enabled by default
#   3.3  Ciclo de vida               → configurable lifecycle rules
#   3.4  Object Lock                 → optional (var.object_lock_enabled)
#   4.1  Cifrado en reposo           → SSE-KMS with existing CMK
#   4.4  Cifrado en tránsito         → HTTPS enforcement via bucket policy
#   5.1  Logs                        → S3 access logging to central bucket
#   6.1  Respaldo y recuperación     → versioning + lifecycle

# ══════════════════════════════════════════════════════════════════════════════
# IDENTITY
# ══════════════════════════════════════════════════════════════════════════════

variable "service" {
  description = "Short service / product name used in resource naming. E.g. 'bancamovil', 'pagos'."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service))
    error_message = "service must be lowercase alphanumeric and hyphens only."
  }
}

variable "workload" {
  description = "Short name of this workload — used as the name suffix. E.g. 'ga4', 'eventos', 'raw'."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workload))
    error_message = "workload must be lowercase alphanumeric and hyphens only."
  }
}

variable "ambiente" {
  description = "Environment name. Must match one of the known tiers."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "preprod", "prod", "dr"], var.ambiente)
    error_message = "ambiente must be one of: dev, qa, preprod, prod, dr."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# REGION
# ══════════════════════════════════════════════════════════════════════════════

variable "aws_region" {
  description = "AWS region where the bucket will be created."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 (primary) or us-east-2 (DR)."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# ACCOUNT GUARDRAIL
# ══════════════════════════════════════════════════════════════════════════════

variable "aws_account_id" {
  description = "Target AWS account ID — guardrail to prevent wrong-account applies."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# ENCRYPTION (KMS)
# ══════════════════════════════════════════════════════════════════════════════

variable "kms_key_alias" {
  description = "Alias of the pre-existing KMS CMK for S3 encryption. Discovered by alias (account baseline). Pass kms_key_arn to override."
  type        = string
  default     = "alias/S3"
}

variable "kms_key_arn" {
  description = "Explicit KMS key ARN override. When set, kms_key_alias is ignored."
  type        = string
  default     = ""
}

# ══════════════════════════════════════════════════════════════════════════════
# VERSIONING & OBJECT LOCK
# ══════════════════════════════════════════════════════════════════════════════

variable "versioning_enabled" {
  description = "Enable versioning on the bucket (security baseline control 3.1). Strongly recommended."
  type        = bool
  default     = true
}

variable "object_lock_enabled" {
  description = "Enable Object Lock (WORM) on the bucket (control 3.4). Must be set at bucket creation time — cannot be enabled later. For production critical buckets."
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object Lock retention mode: GOVERNANCE or COMPLIANCE. Only used when object_lock_enabled = true."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Object Lock retention period in days. Only used when object_lock_enabled = true."
  type        = number
  default     = 30
}

# ══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE RULES
# ══════════════════════════════════════════════════════════════════════════════

variable "lifecycle_enabled" {
  description = "Enable lifecycle rules on the bucket (control 3.3). Controls data retention and cost optimization."
  type        = bool
  default     = true
}

variable "lifecycle_transition_ia_days" {
  description = "Days after which objects transition to Infrequent Access storage class."
  type        = number
  default     = 30
}

variable "lifecycle_transition_glacier_days" {
  description = "Days after which objects transition to Glacier storage class. Set to 0 to skip glacier transition."
  type        = number
  default     = 90
}

variable "lifecycle_expiration_days" {
  description = "Days after which objects expire (are deleted). Set to 0 to never expire."
  type        = number
  default     = 365
}

variable "lifecycle_noncurrent_expiration_days" {
  description = "Days after which non-current versions expire."
  type        = number
  default     = 90
}

# ══════════════════════════════════════════════════════════════════════════════
# ACCESS LOGGING
# ══════════════════════════════════════════════════════════════════════════════

variable "logging_bucket_name" {
  description = "Name of the S3 bucket where access logs will be delivered (control 5.1)."
  type        = string
}

variable "logging_prefix" {
  description = "Prefix for S3 access logs within the logging bucket. Defaults to 's3-access-logs/{service}-{workload}-{ambiente}/'."
  type        = string
  default     = ""
}

# ══════════════════════════════════════════════════════════════════════════════
# BUCKET POLICY — CONSUMER PRINCIPALS
# ══════════════════════════════════════════════════════════════════════════════

variable "reader_principal_arns" {
  description = "List of IAM principal ARNs that can READ from the bucket (s3:GetObject, s3:ListBucket). E.g. Stratio user/role ARN."
  type        = list(string)
  default     = []
}

variable "writer_principal_arns" {
  description = "List of IAM principal ARNs that can WRITE to the bucket (s3:PutObject). E.g. Kinesis Firehose delivery role ARN."
  type        = list(string)
  default     = []
}

# ══════════════════════════════════════════════════════════════════════════════
# MANDATORY TAGS
# ══════════════════════════════════════════════════════════════════════════════

variable "aplicacion" {
  description = "[MANDATORY TAG] Name of the application that owns this bucket."
  type        = string
}

variable "propietario_recurso" {
  description = "[MANDATORY TAG] Resource owner (team or person responsible)."
  type        = string
}

variable "producto" {
  description = "[MANDATORY TAG] Product or business unit."
  type        = string
}

variable "centro_costo" {
  description = "[MANDATORY TAG] Cost center code for billing allocation."
  type        = string
}

variable "extra_tags" {
  description = "Optional additional tags to merge with the mandatory tag set."
  type        = map(string)
  default     = {}
}
