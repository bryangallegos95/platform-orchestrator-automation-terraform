output "endpoint_ids" {
  description = "Map of service name to VPC Endpoint ID."
  value       = { for k, v in aws_vpc_endpoint.this : k => v.id }
}

output "endpoint_dns_entries" {
  description = "Map of service name to primary DNS entry."
  value       = { for k, v in aws_vpc_endpoint.this : k => v.dns_entry[0].dns_name }
}

output "phz_zone_ids" {
  description = "Map of service name to Route 53 PHZ zone ID."
  value       = { for k, v in aws_route53_zone.endpoint : k => v.zone_id }
}

output "endpoint_subnet_a_id" {
  value = aws_subnet.endpoint_a.id
}

output "endpoint_subnet_b_id" {
  value = aws_subnet.endpoint_b.id
}

output "security_group_id" {
  value = aws_security_group.vpce.id
}
