# modules/openshift/account-bootstrap/versions.tf
#
# Account-wide ROSA HCP IAM roles. Run ONCE per AWS account, BEFORE any cluster.
# Standardized tool/provider versions (org fleet standard).

terraform {
  required_version = "~> 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6, >= 1.6.2"
    }
  }
}
