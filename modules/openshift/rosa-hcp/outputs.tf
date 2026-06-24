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
