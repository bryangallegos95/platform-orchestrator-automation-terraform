# modules/openshift/cluster-config/versions.tf
#
# Day-1 IDP configuration via OCM. No AWS resources are created — only the
# rhcs provider is needed. RHCS_TOKEN is consumed from the environment.
#
# ⚠️ rhcs PIN: same constraint as the rosa-hcp module.
#   "~> 1.6.2" allows only 1.6.z patches.
#   1.7.x regressed rosa_creator_arn derivation AND changed IDP attribute names
#   in some cases. Keep pinned until upstream confirms 1.7.x is stable for HCP.
#   Revisit when rosa-hcp module bumps its pin.

terraform {
  required_version = "~> 1.11"

  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6.2"
    }
  }
}
