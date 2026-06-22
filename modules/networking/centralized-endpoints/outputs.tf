# modules/networking/centralized-endpoints/outputs.tf

output "endpoint_ids" {
  description = "Map of service name → VPC endpoint ID."
  value       = { for k, v in aws_vpc_endpoint.this : k => v.id }
}

output "endpoint_dns_entries" {
  description = "Map of service name → primary endpoint DNS name."
  value       = { for k, v in aws_vpc_endpoint.this : k => v.dns_entry[0].dns_name }
}

output "phz_zone_ids" {
  description = "Map of service name → Route 53 PHZ zone ID."
  value       = { for k, v in aws_route53_zone.endpoint : k => v.zone_id }
}

output "security_group_id" {
  description = "Security group ID protecting the interface endpoints."
  value       = aws_security_group.vpce.id
}

# ── Association visibility (v1.3.1) ──────────────────────────────────
output "same_account_associations" {
  description = "Same-account spoke PHZ associations created directly by this module (key → {endpoint, vpc_id, region})."
  value = {
    for k, v in aws_route53_zone_association.spoke_same_account :
    k => { zone_id = v.zone_id, vpc_id = v.vpc_id, vpc_region = v.vpc_region }
  }
}

output "cross_account_authorizations" {
  description = "Cross-account authorizations created by this module. The SPOKE account must run a matching aws_route53_zone_association to accept each one."
  value = {
    for k, v in aws_route53_vpc_association_authorization.spoke_cross_account :
    k => { zone_id = v.zone_id, vpc_id = v.vpc_id }
  }
}
