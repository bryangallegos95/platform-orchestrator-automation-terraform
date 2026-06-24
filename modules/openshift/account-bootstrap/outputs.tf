# modules/openshift/account-bootstrap/outputs.tf

output "account_role_prefix" {
  description = "Prefix of the shared account roles. Pass to every rosa-hcp cluster in this account."
  value       = var.account_role_prefix
}

output "account_roles_arn" {
  description = "ARNs of the created account roles (Installer, Support, Worker)."
  value       = module.account_iam_roles.account_roles_arn
}
