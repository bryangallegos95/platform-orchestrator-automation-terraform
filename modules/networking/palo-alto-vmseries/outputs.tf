# modules/networking/palo-alto-vmseries/outputs.tf
#
# Outputs for consumption by other layers (routing, monitoring, etc.)

# ── GWLB Endpoints (needed by routing layer to redirect TGW traffic) ──────────

output "gwlbe_ids" {
  description = "GWLB Endpoint IDs (one per AZ). Used in TGW subnet route tables."
  value       = aws_vpc_endpoint.gwlbe[*].id
}

output "gwlbe_arns" {
  description = "GWLB Endpoint ARNs"
  value       = aws_vpc_endpoint.gwlbe[*].arn
}

output "vpce_service_name" {
  description = "VPC Endpoint Service name for the GWLB"
  value       = aws_vpc_endpoint_service.gwlb.service_name
}

# ── GWLB ──────────────────────────────────────────────────────────────────────

output "gwlb_arn" {
  description = "Gateway Load Balancer ARN"
  value       = aws_lb.gwlb.arn
}

output "gwlb_dns_name" {
  description = "Gateway Load Balancer DNS name"
  value       = aws_lb.gwlb.dns_name
}

# ── ASG ───────────────────────────────────────────────────────────────────────

output "asg_name" {
  description = "Auto Scaling Group name (for DR failover: set desired_capacity)"
  value       = aws_autoscaling_group.vmseries.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.vmseries.arn
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.vmseries.id
}

# ── Networking (subnets created by this module) ───────────────────────────────

output "gwlbe_subnet_ids" {
  description = "GWLB Endpoint subnet IDs created by this module"
  value       = aws_subnet.gwlbe[*].id
}

output "mgmt_subnet_ids" {
  description = "Management subnet IDs created by this module"
  value       = aws_subnet.mgmt[*].id
}

# ── Security Groups ──────────────────────────────────────────────────────────

output "data_plane_sg_id" {
  description = "Data-plane security group ID"
  value       = aws_security_group.data_plane.id
}

output "mgmt_sg_id" {
  description = "Management security group ID"
  value       = aws_security_group.mgmt.id
}

# ── Bootstrap ─────────────────────────────────────────────────────────────────

output "bootstrap_bucket_name" {
  description = "S3 bootstrap bucket name (empty if not created by this module)"
  value       = var.create_bootstrap_bucket ? aws_s3_bucket.bootstrap[0].id : var.bootstrap_bucket_name
}

output "bootstrap_bucket_arn" {
  description = "S3 bootstrap bucket ARN (empty if not created by this module)"
  value       = var.create_bootstrap_bucket ? aws_s3_bucket.bootstrap[0].arn : ""
}

# ── Lambda ────────────────────────────────────────────────────────────────────

output "lifecycle_lambda_arn" {
  description = "Lifecycle management Lambda function ARN"
  value       = aws_lambda_function.lifecycle.arn
}

# ── CloudWatch ────────────────────────────────────────────────────────────────

output "log_group_traffic" {
  description = "CloudWatch log group for PA traffic logs"
  value       = aws_cloudwatch_log_group.traffic.name
}

output "log_group_threat" {
  description = "CloudWatch log group for PA threat logs"
  value       = aws_cloudwatch_log_group.threat.name
}
