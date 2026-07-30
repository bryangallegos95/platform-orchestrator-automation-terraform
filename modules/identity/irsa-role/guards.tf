# modules/identity/irsa-role/guards.tf
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
      condition     = var.oidc_issuer_url != ""
      error_message = "oidc_issuer_url is required. Obtain it from: terragrunt output -raw oidc_endpoint_url (in the rosa-negocio-{env}/ component)."
    }

    # Validate that the OIDC provider was found
    precondition {
      condition     = data.aws_iam_openid_connect_provider.rosa.arn != ""
      error_message = "OIDC provider not found for URL '${var.oidc_issuer_url}'. Ensure the ROSA cluster is deployed and the OIDC provider exists in account ${var.aws_account_id}."
    }
  }
}
