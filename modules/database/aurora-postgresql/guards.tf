# modules/database/aurora-postgresql/guards.tf
#
# Plan-time guardrails. Uses terraform_data (built-in, Terraform >= 1.4) —
# no external provider. The Aurora cluster depends_on this resource, so every
# apply fails fast here BEFORE any resource is touched if a guard is violated.
#
# Guards:
#   1. Account guard  — the workflow-provided account must match the active
#      account, else the VPC/subnet/KMS lookups would silently target the
#      wrong account.
#   2. Region guard   — the provider's active region must equal var.aws_region,
#      and DR must run in us-east-2. Prevents a cluster landing in the wrong
#      region (wrong Spoke VPC / wrong DR posture).

resource "terraform_data" "guards" {
  lifecycle {
    # 1. Account guard
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id}). Cluster and discovered VPC/KMS must be in the SAME account."
    }

    # 2a. Provider region must match the declared region.
    precondition {
      condition     = data.aws_region.current.name == var.aws_region
      error_message = "Active provider region (${data.aws_region.current.name}) != var.aws_region (${var.aws_region}). The generated provider region and the module region must agree."
    }

    # 2b. DR is only ever us-east-2 (bank baseline). Prevents a dr apply in ue1.
    precondition {
      condition     = var.ambiente != "dr" || var.aws_region == "us-east-2"
      error_message = "ambiente=dr must run in us-east-2 (got ${var.aws_region}). DR region is fixed by the platform."
    }
  }
}
