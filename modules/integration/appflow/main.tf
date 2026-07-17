# modules/integration/appflow/main.tf
#
# AWS AppFlow — Flow from source (GA4) to destination (Kinesis Firehose).
#
# What this module creates:
#   1. AppFlow Flow (source connector → Firehose destination)
#   2. IAM role for AppFlow service (see iam.tf)
#   3. Flow tasks (field mappings — default: MAP_ALL)
#
# What this module does NOT create:
#   - Connector Profile (OAuth2 for GA4 must be configured manually in console
#     or via a separate resource — AppFlow connector profiles for Google services
#     require interactive OAuth consent that cannot be fully automated via IaC)
#   - Kinesis Firehose stream (input from kinesis-firehose module)
#   - VPC Endpoint for AppFlow (managed in the centralized services layer)
#
# NOTE ON CONNECTOR PROFILES:
#   For GA4, the connector profile includes OAuth2 tokens that require
#   interactive authorization flow (Google consent screen). The recommended
#   approach is:
#     1. Create the connector profile manually in the AWS Console
#     2. Reference it via var.source_connector_profile_name
#     3. The flow itself is fully managed by Terraform

# ══════════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ══════════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}

# ══════════════════════════════════════════════════════════════════════════════
# ACCOUNT GUARDRAIL
# ══════════════════════════════════════════════════════════════════════════════

resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id})."
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# APPFLOW FLOW
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_appflow_flow" "this" {
  name        = local.flow_name
  description = var.flow_description != "" ? var.flow_description : "AppFlow - ${var.source_connector_type} to Kinesis Firehose - ${var.service}-${var.workload}-${var.ambiente}"

  # ── Source ────────────────────────────────────────────────────────────────
  source_flow_config {
    connector_type         = var.source_connector_type
    connector_profile_name = var.source_connector_profile_name != "" ? var.source_connector_profile_name : local.connector_profile_name
    api_version            = var.source_connector_type == "CustomConnector" ? "v1" : null

    source_connector_properties {
      dynamic "custom_connector" {
        for_each = var.source_connector_type == "CustomConnector" ? [1] : []
        content {
          entity_name = var.source_object
        }
      }
    }
  }

  # ── Destination (Kinesis Firehose) ────────────────────────────────────────
  destination_flow_config {
    connector_type = "EventBridge"

    destination_connector_properties {
      event_bridge {
        object = var.destination_firehose_arn
      }
    }
  }

  # ── Trigger ───────────────────────────────────────────────────────────────
  trigger_config {
    trigger_type = var.trigger_type

    dynamic "trigger_properties" {
      for_each = var.trigger_type == "Scheduled" ? [1] : []
      content {
        scheduled {
          schedule_expression = var.schedule_expression
          schedule_offset     = var.schedule_offset
          data_pull_mode      = "Incremental"
        }
      }
    }
  }

  # ── Tasks (Field mappings) ────────────────────────────────────────────────
  # Default: MAP_ALL — passes all source fields to destination as-is.
  # Son repos can override with specific field mappings via var.tasks.
  dynamic "task" {
    for_each = length(var.tasks) > 0 ? var.tasks : [{
      source_fields      = []
      task_type          = "Map_all"
      connector_operator = {}
      destination_field  = ""
      task_properties    = {}
    }]
    content {
      source_fields = task.value.source_fields
      task_type     = task.value.task_type

      dynamic "connector_operator" {
        for_each = length(task.value.connector_operator) > 0 ? [task.value.connector_operator] : []
        content {
          # Dynamic connector operator based on source type
        }
      }

      destination_field = task.value.destination_field != "" ? task.value.destination_field : null
      task_properties   = length(task.value.task_properties) > 0 ? task.value.task_properties : null
    }
  }

  tags = merge(local.tags, { Name = local.flow_name })

  depends_on = [terraform_data.account_guard]
}
