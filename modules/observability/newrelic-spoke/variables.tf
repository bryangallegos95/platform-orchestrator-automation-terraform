# modules/observability/newrelic-spoke/variables.tf
#
# Inputs for the New Relic spoke module.
# Creates CloudWatch Logs subscription filters that forward workload logs
# to a centralized hub (Kinesis Firehose → New Relic) via a cross-account
# CloudWatch Logs Destination.

# ═══════════════════════════════════════════════════════════════════════════════
# CORE IDENTITY
# ═══════════════════════════════════════════════════════════════════════════════

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
}

variable "service" {
  description = "OU name (lowercase) used for naming."
  type        = string
}

variable "workload" {
  description = "Short workload name. Used in resource naming."
  type        = string
}

variable "funcionalidad" {
  description = "Specific purpose within the workload. Used in naming."
  type        = string
}

variable "ambiente" {
  description = "Environment name (dev/qa/preprod/prod/dr)."
  type        = string
}

variable "aws_account_id" {
  description = "Target AWS account ID (12-digit). Used in IAM trust conditions."
  type        = string
}

# ═══════════════════════════════════════════════════════════════════════════════
# NEW RELIC SPOKE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

variable "log_group_names" {
  description = "List of CloudWatch Log Group names to subscribe to the hub destination. Each gets a subscription filter."
  type        = list(string)
}

variable "hub_destination_arn" {
  description = "ARN of the centralized CloudWatch Logs Destination (cross-account) or Kinesis Data Stream that receives forwarded logs."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:(logs|kinesis):[a-z0-9-]+:[0-9]{12}:", var.hub_destination_arn))
    error_message = "hub_destination_arn must be a valid ARN for a CloudWatch Logs Destination or Kinesis Data Stream."
  }
}

variable "filter_pattern" {
  description = "CloudWatch Logs filter pattern. Empty string means all log events are forwarded."
  type        = string
  default     = ""
}
