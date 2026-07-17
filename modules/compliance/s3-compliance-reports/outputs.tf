# modules/compliance/s3-compliance-reports/outputs.tf

output "bucket_name" {
  description = "Name of the compliance reports bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the compliance reports bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "ID of the compliance reports bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption."
  value       = local.kms_key_arn
}

output "prowler_prefix" {
  description = "S3 prefix for Prowler reports."
  value       = "prowler/"
}

output "finops_prefix" {
  description = "S3 prefix for FinOps reports."
  value       = "finops/"
}

output "tag_audit_prefix" {
  description = "S3 prefix for tag compliance audit reports."
  value       = "tag-audit/"
}

output "deployments_prefix" {
  description = "S3 prefix for deployment records."
  value       = "deployments/"
}
