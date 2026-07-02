# modules/compute/ec2/outputs.tf
#
# Exposes all identifiers that son-repo stacks or other modules may need.
# Pattern: one output per resource, plus discovery context for traceability.

# ── Instance ──────────────────────────────────────────────────────────────────
output "instance_id" {
  description = "ID of the EC2 instance."
  value       = aws_instance.this.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance."
  value       = aws_instance.this.arn
}

output "instance_name" {
  description = "Name tag of the instance (follows naming convention)."
  value       = local.instance_name
}

output "private_ip" {
  description = "Primary private IP of the instance."
  value       = aws_instance.this.private_ip
}

output "private_dns" {
  description = "Private DNS name of the instance."
  value       = aws_instance.this.private_dns
}

output "availability_zone" {
  description = "AZ the instance was placed in."
  value       = aws_instance.this.availability_zone
}

output "ami_id" {
  description = "AMI the instance was launched from (pinned at creation time)."
  value       = aws_instance.this.ami
}

# ── Security Group ────────────────────────────────────────────────────────────
output "security_group_id" {
  description = "ID of the module-managed Security Group. Reference it from other SGs to allow traffic to this instance."
  value       = aws_security_group.this.id
}

# ── IAM ───────────────────────────────────────────────────────────────────────
output "iam_role_name" {
  description = "Name of the instance IAM role — attach extra inline policies to it if needed."
  value       = aws_iam_role.this.name
}

output "iam_role_arn" {
  description = "ARN of the instance IAM role — use for KMS key policies, bucket policies, etc."
  value       = aws_iam_role.this.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile."
  value       = aws_iam_instance_profile.this.name
}

# ── Discovery context (traceability) ──────────────────────────────────────────
output "vpc_id" {
  description = "ID of the discovered Spoke VPC the instance lives in."
  value       = data.aws_vpc.spoke.id
}

output "subnet_id" {
  description = "ID of the discovered subnet the instance was placed in."
  value       = data.aws_subnet.target.id
}
