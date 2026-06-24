# modules/openshift/rosa-hcp/versions.tf
#
# ROSA HCP cluster module. Standardized fleet tool/provider versions.
#   Terraform : ~> 1.11
#   AWS       : ~> 6.51
#   rhcs      : ~> 1.6, >= 1.6.2

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
