# modules/database/dynamodb/guards.tf
#
# Plan-time guardrails. Uses terraform_data (built-in, Terraform >= 1.4) —
# no external provider. Every table depends_on this resource, so an apply fails
# fast here BEFORE any table is touched if a guard is violated.
#
# Guards:
#   1. Account guard — the workflow-provided account must match the active
#      account, else the KMS alias lookup would silently target the wrong key.
#   2. Region guard  — the provider's active region must equal var.aws_region.
#      DynamoDB tables are regional; a wrong region creates a second, empty
#      table set instead of failing.
#
# TODO: validar contra platform-knowledge-base — DR.
#   aurora-postgresql añade un tercer guard (`ambiente=dr` ⇒ `us-east-2`) porque
#   su DR es Global Database. Para DynamoDB no hay todavía postura de DR
#   definida (Global Tables vs. backup cross-region vs. sin DR), así que no se
#   asume ninguna. Cuando se defina, el guard equivalente va aquí:
#
#     precondition {
#       condition     = var.ambiente != "dr" || var.aws_region == "us-east-2"
#       error_message = "ambiente=dr must run in us-east-2."
#     }

resource "terraform_data" "guards" {
  lifecycle {
    # 1. Account guard
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id}). Tables and discovered CMK must be in the SAME account."
    }

    # 2. Provider region must match the declared region.
    precondition {
      condition     = data.aws_region.current.name == var.aws_region
      error_message = "Active provider region (${data.aws_region.current.name}) != var.aws_region (${var.aws_region}). The generated provider region and the module region must agree."
    }
  }
}
