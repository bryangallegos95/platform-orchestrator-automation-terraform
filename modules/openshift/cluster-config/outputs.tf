# modules/openshift/cluster-config/outputs.tf

output "htpasswd_idp_id" {
  description = "OCM ID of the htpasswd IDP. Empty string when enable_htpasswd = false."
  value       = var.enable_htpasswd ? rhcs_identity_provider.htpasswd[0].id : ""
}

output "entra_idp_id" {
  description = "OCM ID of the EntraID openid IDP."
  value       = rhcs_identity_provider.entra_id.id
}

output "entra_idp_name" {
  description = "Name of the EntraID IDP as registered in OCM (used by oc login --provider)."
  value       = rhcs_identity_provider.entra_id.name
}
