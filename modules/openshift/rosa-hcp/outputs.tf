# modules/openshift/rosa-hcp/outputs.tf
#
# Outputs feed the NEXT steps: ACM import + ArgoCD registration.

output "cluster_id" {
  description = "ROSA HCP cluster ID (for ACM import / rosa CLI)."
  value       = rhcs_cluster_rosa_hcp.this.id
}

output "cluster_name" {
  description = "Cluster name."
  value       = rhcs_cluster_rosa_hcp.this.name
}

output "api_url" {
  description = "Private API server URL (reachable via TGW/VPN only)."
  value       = rhcs_cluster_rosa_hcp.this.api_url
}

output "console_url" {
  description = "Private console URL."
  value       = rhcs_cluster_rosa_hcp.this.console_url
}

output "oidc_endpoint_url" {
  description = "Cluster OIDC endpoint."
  value       = module.oidc_config_and_provider.oidc_endpoint_url
}

output "discovered_vpc_id" {
  description = "VPC discovered by tag (sanity)."
  value       = data.aws_vpc.rosa.id
}

output "discovered_subnet_ids" {
  description = "ROSA subnets discovered by tag (sanity)."
  value       = data.aws_subnets.rosa.ids
}

output "machine_cidr_used" {
  description = "Machine CIDR derived from the discovered VPC."
  value       = local.machine_cidr
}

output "cp_security_group_id" {
  description = "ID of the additional Security Group associated with the ROSA HCP Control-Plane PrivateLink endpoint. Null when cp_ingress_cidrs is empty."
  value       = length(var.cp_ingress_cidrs) > 0 ? aws_security_group.rosa_cp[0].id : null
}

output "cp_vpc_endpoint_id" {
  description = "ID of the ROSA HCP Control-Plane PrivateLink VPC Endpoint discovered in the cluster VPC. Null when cp_ingress_cidrs is empty."
  value       = length(var.cp_ingress_cidrs) > 0 ? data.aws_vpc_endpoint.rosa_api[0].id : null
}
