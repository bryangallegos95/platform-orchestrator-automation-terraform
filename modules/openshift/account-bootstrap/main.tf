# modules/openshift/account-bootstrap/main.tf
#
# Creates the SHARED ROSA HCP account roles (Installer, Support, Worker) for this
# AWS account, using Red Hat's official account-iam-resources submodule (it encodes
# the exact, version-aware IAM policies ROSA requires).
#
# Lifecycle ownership: this unit OWNS the account roles. A cluster's destroy MUST
# NOT remove these — that is precisely why they live in this separate unit and not
# in the per-cluster rosa-hcp module.

module "account_iam_roles" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/account-iam-resources"
  version = "~> 1.6, >= 1.6.2"

  account_role_prefix = var.account_role_prefix
  openshift_version   = var.openshift_version_minor

  tags = local.tags
}
