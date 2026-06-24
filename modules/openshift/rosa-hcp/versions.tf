# modules/openshift/rosa-hcp/versions.tf
#
# ROSA HCP cluster module. Standardized fleet tool/provider versions.
#   Terraform : ~> 1.11
#   AWS       : ~> 6.51
#   rhcs      : ~> 1.6.2  (PINNED to 1.6.x — do NOT allow 1.7.x; see note)
#
# ⚠️ rhcs PIN NOTE: "~> 1.6, >= 1.6.2" ALLOWED 1.7.x (it resolved to 1.7.7),
# which changed the OCM auth / rosa_creator_arn derivation and broke cluster
# creation. We pin to the 1.6.x line with "~> 1.6.2" so only 1.6.z patches apply.

terraform {
  required_version = "~> 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6.2"
    }
  }
}
