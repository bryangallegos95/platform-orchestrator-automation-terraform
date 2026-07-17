# modules/integration/kinesis-firehose/variables.tf
#
# All inputs for the Kinesis Data Firehose delivery stream module.
#
# This module creates a Firehose delivery stream with:
#   - Source: Direct PUT (AppFlow delivers data directly)
#   - Destination: S3 with format conversion (Apache Parquet)
#   - IAM role for delivery (S3 + KMS + CloudWatch)
#   - CloudWatch error logging
#
# The stream receives data from AppFlow and delivers it to S3 in
# Apache Parquet format with Snappy compression for efficient
# columnar storage and query performance.

# ══════════════════════════════════════════════════════════════════════════════
# IDENTITY
# ══════════════════════════════════════════════════════════════════════════════

variable "service" {
  description = "Short service / product name used in resource naming. E.g. 'payments', 'analytics'."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service))
    error_message = "service must be lowercase alphanumeric and hyphens only."
  }
}

variable "workload" {
  description = "Short name of this workload — used as the name suffix. E.g. 'ga4', 'eventos'."
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
  description = "AWS region where the delivery stream will be created."
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
# S3 DESTINATION
# ══════════════════════════════════════════════════════════════════════════════

variable "destination_bucket_arn" {
  description = "ARN of the destination S3 bucket (from s3-private module output)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.destination_bucket_arn))
    error_message = "destination_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "s3_prefix" {
  description = "S3 key prefix for delivered objects. Firehose appends YYYY/MM/DD/HH. E.g. 'raw/' → raw/2024/01/15/08/file.parquet"
  type        = string
  default     = "raw/"
}

variable "s3_error_prefix" {
  description = "S3 key prefix for failed deliveries. Firehose appends error type and timestamp."
  type        = string
  default     = "errors/"
}

# ══════════════════════════════════════════════════════════════════════════════
# KMS — For S3 delivery encryption
# ══════════════════════════════════════════════════════════════════════════════

variable "kms_key_arn" {
  description = "ARN of the KMS key used by the destination S3 bucket (for Firehose to encrypt objects). Pass the s3-private module's kms_key_arn output."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid KMS key ARN."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# FORMAT CONVERSION (Apache Parquet)
# ══════════════════════════════════════════════════════════════════════════════

variable "output_format" {
  description = "Output serialization format: PARQUET, ORC, or DISABLED (JSON passthrough)."
  type        = string
  default     = "PARQUET"

  validation {
    condition     = contains(["PARQUET", "ORC", "DISABLED"], var.output_format)
    error_message = "output_format must be PARQUET, ORC, or DISABLED."
  }
}

variable "parquet_compression" {
  description = "Compression codec for Parquet output: SNAPPY, GZIP, or UNCOMPRESSED."
  type        = string
  default     = "SNAPPY"

  validation {
    condition     = contains(["SNAPPY", "GZIP", "UNCOMPRESSED"], var.parquet_compression)
    error_message = "parquet_compression must be SNAPPY, GZIP, or UNCOMPRESSED."
  }
}

variable "schema_table_name" {
  description = "Glue Catalog table name for schema (format conversion). Required when output_format != DISABLED."
  type        = string
  default     = ""
}

variable "schema_database_name" {
  description = "Glue Catalog database name for schema (format conversion). Required when output_format != DISABLED."
  type        = string
  default     = ""
}

variable "schema_region" {
  description = "Region of the Glue Catalog. Defaults to aws_region."
  type        = string
  default     = ""
}

variable "schema_role_arn" {
  description = "IAM role ARN for Glue Catalog access. Defaults to the Firehose delivery role."
  type        = string
  default     = ""
}

# ══════════════════════════════════════════════════════════════════════════════
# BUFFERING
# ══════════════════════════════════════════════════════════════════════════════

variable "buffering_interval_seconds" {
  description = "Buffer interval in seconds before delivering to S3. Range: 0-900."
  type        = number
  default     = 300

  validation {
    condition     = var.buffering_interval_seconds >= 0 && var.buffering_interval_seconds <= 900
    error_message = "buffering_interval_seconds must be between 0 and 900."
  }
}

variable "buffering_size_mb" {
  description = "Buffer size in MB before delivering to S3. Range: 1-128."
  type        = number
  default     = 64

  validation {
    condition     = var.buffering_size_mb >= 1 && var.buffering_size_mb <= 128
    error_message = "buffering_size_mb must be between 1 and 128."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# CLOUDWATCH LOGGING
# ══════════════════════════════════════════════════════════════════════════════

variable "log_retention_days" {
  description = "CloudWatch Log Group retention period for Firehose error logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# MANDATORY TAGS
# ══════════════════════════════════════════════════════════════════════════════

variable "aplicacion" {
  description = "[MANDATORY TAG] Name of the application."
  type        = string
}

variable "propietario_recurso" {
  description = "[MANDATORY TAG] Resource owner."
  type        = string
}

variable "producto" {
  description = "[MANDATORY TAG] Product or business unit."
  type        = string
}

variable "centro_costo" {
  description = "[MANDATORY TAG] Cost center code."
  type        = string
}

variable "extra_tags" {
  description = "Optional additional tags."
  type        = map(string)
  default     = {}
}
