# modules/integration/appflow/variables.tf
#
# All inputs for the AWS AppFlow module.
#
# This module creates an AppFlow flow that:
#   - Connects to a source (e.g. Google Analytics 4) via a connector profile
#   - Delivers data to a Kinesis Data Firehose delivery stream
#   - Runs on a schedule or on-demand
#   - Uses PrivateLink for secure connectivity (via VPC Endpoint)

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
  description = "AWS region where the flow will be created."
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
# SOURCE — CONNECTOR PROFILE
# ══════════════════════════════════════════════════════════════════════════════

variable "source_connector_type" {
  description = "Source connector type. Use 'CustomConnector' for third-party connectors with connector_label. Native types: 'Salesforce', 'S3', 'Zendesk', 'Marketo', etc."
  type        = string
  default     = "CustomConnector"
}

variable "source_connector_profile_name" {
  description = "Name of an existing AppFlow connector profile to use as source. If empty, the module creates one using the provided credentials."
  type        = string
  default     = ""
}

variable "source_connector_label" {
  description = "Connector label when using CustomConnector type. Required when source_connector_type = 'CustomConnector'. Leave empty for native connector types."
  type        = string
  default     = ""
}

variable "source_object" {
  description = "Source object identifier. The value depends on the connector type (e.g. property ID, object name, table name)."
  type        = string
}

# ══════════════════════════════════════════════════════════════════════════════
# DESTINATION — KINESIS FIREHOSE
# ══════════════════════════════════════════════════════════════════════════════

variable "destination_firehose_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream (from kinesis-firehose module output)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:firehose:", var.destination_firehose_arn))
    error_message = "destination_firehose_arn must be a valid Firehose delivery stream ARN."
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# FLOW CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

variable "trigger_type" {
  description = "Flow trigger type: Scheduled, OnDemand, or Event."
  type        = string
  default     = "Scheduled"

  validation {
    condition     = contains(["Scheduled", "OnDemand", "Event"], var.trigger_type)
    error_message = "trigger_type must be Scheduled, OnDemand, or Event."
  }
}

variable "schedule_expression" {
  description = "Schedule expression for the flow (cron or rate). Only used when trigger_type = Scheduled. E.g. 'rate(1hour)', 'rate(6hours)'."
  type        = string
  default     = "rate(1hour)"
}

variable "schedule_offset" {
  description = "Offset in seconds for the schedule start time. Helps distribute load."
  type        = number
  default     = 0
}

variable "flow_description" {
  description = "Description of the AppFlow flow."
  type        = string
  default     = ""
}

# ══════════════════════════════════════════════════════════════════════════════
# FIELD MAPPINGS
# ══════════════════════════════════════════════════════════════════════════════

variable "tasks" {
  description = <<-EOT
    List of AppFlow tasks (field mappings, filters, etc.).
    Each task is an object with: source_fields, task_type, connector_operator, destination_field, task_properties.
    If empty, a default MAP_ALL task is created (pass all fields as-is).
  EOT
  type = list(object({
    source_fields      = list(string)
    task_type          = string
    connector_operator = optional(map(string), {})
    destination_field  = optional(string, "")
    task_properties    = optional(map(string), {})
  }))
  default = []
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
