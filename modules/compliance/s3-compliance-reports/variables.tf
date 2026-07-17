# modules/compliance/s3-compliance-reports/variables.tf
#
# S3 Bucket for centralized compliance reports (Prowler, FinOps, Tag Audit).

# ══════════════════════════════════════════════════════════════════════════════
# IDENTITY
# ══════════════════════════════════════════════════════════════════════════════

variable "ambiente" {
  description = "Environment: dev | qa | preprod | prod | dr."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "preprod", "prod", "dr"], var.ambiente)
    error_message = "ambiente must be one of: dev, qa, preprod, prod, dr."
  }
}

variable "aws_region" {
  description = "AWS region where the bucket will be created."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 (primary) or us-east-2 (DR)."
  }
}

variable "aws_account_id" {
  description = "Target AWS account ID — guardrail to prevent wrong-account applies."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# ENCRYPTION
# ══════════════════════════════════════════════════════════════════════════════

variable "kms_key_alias" {
  description = "Alias of the pre-existing KMS CMK for S3 encryption."
  type        = string
  default     = "alias/S3"
}

variable "kms_key_arn" {
  description = "Explicit KMS key ARN override. When set, kms_key_alias is ignored."
  type        = string
  default     = ""
}

# ══════════════════════════════════════════════════════════════════════════════
# RETENTION
# ══════════════════════════════════════════════════════════════════════════════

variable "report_retention_days" {
  description = "Days to retain compliance reports before transition to IA."
  type        = number
  default     = 90
}

variable "archive_retention_days" {
  description = "Days to retain reports in Glacier before expiration."
  type        = number
  default     = 365
}

variable "expiration_days" {
  description = "Days after which reports are permanently deleted."
  type        = number
  default     = 730
}

# ══════════════════════════════════════════════════════════════════════════════
# ACCESS
# ══════════════════════════════════════════════════════════════════════════════

variable "writer_role_arns" {
  description = "IAM role ARNs allowed to write reports (Prowler runner roles per env)."
  type        = list(string)
  default     = []
}

variable "reader_role_arns" {
  description = "IAM role ARNs allowed to read reports (CloudOps, auditors)."
  type        = list(string)
  default     = []
}

# ══════════════════════════════════════════════════════════════════════════════
# LOGGING
# ══════════════════════════════════════════════════════════════════════════════

variable "logging_bucket_name" {
  description = "S3 bucket for access logging. Must exist in the same account."
  type        = string
  default     = ""
}

# ══════════════════════════════════════════════════════════════════════════════
# TAGS
# ══════════════════════════════════════════════════════════════════════════════

variable "aplicacion" {
  description = "Application name (CloudOps Tier 2 mandatory tag)."
  type        = string
  default     = "PlatformCompliance"
}

variable "propietario_recurso" {
  description = "Resource owner (mandatory tag)."
  type        = string
  default     = "CloudOps"
}

variable "producto" {
  description = "Business product (mandatory tag)."
  type        = string
  default     = "InfraestructuraTransversal"
}

variable "centro_costo" {
  description = "Cost center for FinOps (mandatory tag)."
  type        = string
  default     = "CloudOps"
}

variable "extra_tags" {
  description = "Additional tags to merge."
  type        = map(string)
  default     = {}
}
