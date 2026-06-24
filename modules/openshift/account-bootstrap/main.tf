# modules/openshift/account-bootstrap/main.tf
#
# Creates the SHARED ROSA HCP account roles (Installer, Support, Worker) for this
# AWS account, using Red Hat's official account-iam-resources submodule.
#
# NOTE: account roles use AWS-MANAGED policies (ROSAInstallerPolicy, etc.) which
# are version-agnostic — the submodule therefore takes NO openshift_version input.
#
# Lifecycle ownership: this unit OWNS the account roles. A cluster's destroy MUST
# NOT remove these — that is why they live in this separate unit.

module "account_iam_roles" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/account-iam-resources"
  version = "~> 1.6, >= 1.6.2"

  account_role_prefix = var.account_role_prefix

  tags = local.tags
}
