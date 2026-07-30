# modules/messaging/sqs/guards.tf
#
# Plan-time preconditions — fail fast before creating resources.
# Same pattern as aurora-postgresql/guards.tf.

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
  }
}
