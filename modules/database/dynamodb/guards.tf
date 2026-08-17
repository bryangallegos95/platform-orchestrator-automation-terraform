# modules/database/dynamodb/guards.tf
#
# Plan-time guardrails. Uses terraform_data (built-in, Terraform >= 1.4) — no
# external provider. Every table depends_on this resource, so an apply fails
# fast here BEFORE any table is touched if a guard is violated.
#
# Guards:
#   1. Account guard — the workflow-provided account must match the active
#      account, else the KMS alias lookup would silently resolve a key in the
#      wrong account.
#   2. Region guard  — the provider's active region must equal var.aws_region.
#
# Same pattern as aurora-postgresql/guards.tf and messaging/sqs/guards.tf.

resource "terraform_data" "guards" {
  lifecycle {
    # 1. Account guard
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id}). Tables and the discovered CMK must be in the SAME account."
    }

    # 2. Provider region must match the declared region.
    precondition {
      condition     = data.aws_region.current.name == var.aws_region
      error_message = "Active provider region (${data.aws_region.current.name}) != var.aws_region (${var.aws_region}). The generated provider region and the module region must agree."
    }
  }
}
