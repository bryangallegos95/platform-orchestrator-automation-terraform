# modules/database/elasticache-serverless/guards.tf
#
# Plan-time preconditions — fail fast before creating resources.

resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "Active AWS account (${data.aws_caller_identity.current.account_id}) does not match var.aws_account_id (${var.aws_account_id}). Are you assuming the correct role?"
    }

    precondition {
      condition     = data.aws_region.current.name == var.aws_region
      error_message = "Active provider region (${data.aws_region.current.name}) does not match var.aws_region (${var.aws_region})."
    }

    precondition {
      condition     = !(var.ambiente == "dr" && var.aws_region != "us-east-2")
      error_message = "ambiente=dr must use aws_region=us-east-2."
    }

    # FinOps guard: ECPU ceiling
    precondition {
      condition     = local.effective_max_ecpu <= local.ecpu_ceiling
      error_message = "max_ecpu_per_second (${local.effective_max_ecpu}) exceeds the ${var.ambiente} ceiling of ${local.ecpu_ceiling}. Raise the ceiling in the module if the workload truly needs it."
    }

    # FinOps guard: Storage ceiling
    precondition {
      condition     = local.effective_max_storage <= local.storage_ceiling_gb
      error_message = "max_data_storage_gb (${local.effective_max_storage}) exceeds the ${var.ambiente} ceiling of ${local.storage_ceiling_gb} GB. Raise the ceiling in the module if the workload truly needs it."
    }
  }
}
