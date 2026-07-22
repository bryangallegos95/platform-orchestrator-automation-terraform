# modules/database/aurora-postgresql/versions.tf
#
# Terraform and AWS provider version constraints.
# Pin the provider minor to avoid surprise breaking changes.
# Bump deliberately when the team validates the new version.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
    # terraform_data (built-in) replaces the previous null_resource guard —
    # no external provider needed. Requires Terraform >= 1.4 (satisfied above).
  }
}
