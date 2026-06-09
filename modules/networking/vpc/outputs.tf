# modules/networking/vpc/outputs.tf
#
# Exposes all identifiers that son-repo stacks or other modules may need.
# Pattern: one output per resource, plus convenience grouped outputs (lists).

# ── VPC ───────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID of the spoke VPC."
  value       = aws_vpc.this.id
}

output "vpc_name" {
  description = "Name tag of the spoke VPC (follows naming convention)."
  value       = local.vpc_name
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the spoke VPC."
  value       = aws_vpc.this.cidr_block
}

# ── Subnets — individual ──────────────────────────────────────────────────────
output "subnet_app_a_id" {
  description = "Subnet ID — App tier, AZ-a (us-east-1a)."
  value       = aws_subnet.app_a.id
}

output "subnet_app_b_id" {
  description = "Subnet ID — App tier, AZ-b (us-east-1b)."
  value       = aws_subnet.app_b.id
}

output "subnet_bdd_a_id" {
  description = "Subnet ID — BDD (database) tier, AZ-a."
  value       = aws_subnet.bdd_a.id
}

output "subnet_bdd_b_id" {
  description = "Subnet ID — BDD (database) tier, AZ-b."
  value       = aws_subnet.bdd_b.id
}

output "subnet_gwlb_a_id" {
  description = "Subnet ID — GWLB / API-GW endpoint tier, AZ-a."
  value       = aws_subnet.gwlb_a.id
}

output "subnet_gwlb_b_id" {
  description = "Subnet ID — GWLB / API-GW endpoint tier, AZ-b."
  value       = aws_subnet.gwlb_b.id
}

# ── Subnets — grouped convenience outputs ─────────────────────────────────────
output "subnet_app_ids" {
  description = "List of App subnet IDs [az-a, az-b]. Use for ECS, EC2, Lambda, etc."
  value       = [aws_subnet.app_a.id, aws_subnet.app_b.id]
}

output "subnet_bdd_ids" {
  description = "List of BDD (database) subnet IDs [az-a, az-b]. Use for RDS subnet groups."
  value       = [aws_subnet.bdd_a.id, aws_subnet.bdd_b.id]
}

output "subnet_gwlb_ids" {
  description = "List of GWLB / API-GW endpoint subnet IDs [az-a, az-b]."
  value       = [aws_subnet.gwlb_a.id, aws_subnet.gwlb_b.id]
}

# ── Route Tables ──────────────────────────────────────────────────────────────
output "route_table_private_a_id" {
  description = "Route table ID for AZ-a (shared by all tiers in AZ-a)."
  value       = aws_route_table.private_a.id
}

output "route_table_private_b_id" {
  description = "Route table ID for AZ-b (shared by all tiers in AZ-b)."
  value       = aws_route_table.private_b.id
}

# ── Transit Gateway ───────────────────────────────────────────────────────────
output "tgw_attachment_id" {
  description = "TGW VPC Attachment ID. Use this in the Hub account's TGW route table if needed."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}

# ── VPC Flow Logs ─────────────────────────────────────────────────────────────
output "flow_log_id" {
  description = "ID of the VPC Flow Log resource."
  value       = aws_flow_log.this.id
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name where flow logs are delivered."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "flow_log_group_arn" {
  description = "CloudWatch Log Group ARN — use for metric filters or subscription filters."
  value       = aws_cloudwatch_log_group.flow_logs.arn
}
# ── VPC Endpoints ─────────────────────────────────────────────────────────────
output "vpce_s3_id" {
  description = "VPC Endpoint ID for S3 (if enabled)."
  value       = var.enable_s3_endpoint ? aws_vpc_endpoint.s3[0].id : null
}

output "vpce_dynamodb_id" {
  description = "VPC Endpoint ID for DynamoDB (if enabled)."
  value       = var.enable_dynamodb_endpoint ? aws_vpc_endpoint.dynamodb[0].id : null
}

output "vpce_ssm_id" {
  description = "VPC Endpoint ID for SSM (if enabled)."
  value       = var.enable_ssm_endpoints ? aws_vpc_endpoint.ssm[0].id : null
}

output "vpce_ec2_id" {
  description = "VPC Endpoint ID for EC2 (if enabled)."
  value       = var.enable_ssm_endpoints ? aws_vpc_endpoint.ec2[0].id : null
}

output "vpce_sg_s3_id" {
  description = "Security Group ID for S3 VPC endpoint."
  value       = var.enable_s3_endpoint ? aws_security_group.vpce_s3[0].id : null
}

output "vpce_sg_ec2_ssm_id" {
  description = "Security Group ID for EC2/SSM VPC endpoints."
  value       = var.enable_ssm_endpoints ? aws_security_group.vpce_ec2_ssm[0].id : null
}
