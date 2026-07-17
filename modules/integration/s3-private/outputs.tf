# modules/integration/s3-private/outputs.tf
#
# Exposes all identifiers that son-repo stacks or other modules may need.

# ── Bucket ────────────────────────────────────────────────────────────────────
output "bucket_id" {
  description = "ID (name) of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_name" {
  description = "Name of the S3 bucket (follows naming convention)."
  value       = local.bucket_name
}

output "bucket_domain_name" {
  description = "Bucket domain name (e.g. s3-aw-ue1-myservice-data-dev.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

# ── KMS ───────────────────────────────────────────────────────────────────────
output "kms_key_arn" {
  description = "ARN of the KMS CMK used for bucket encryption."
  value       = local.kms_key_arn
}

# ── For S3A-compatible connectors (Spark, Hadoop) ─────────────────────────────
output "s3a_uri" {
  description = "S3A URI for Spark/Hadoop connectors (fs.defaultFS value)."
  value       = "s3a://${local.bucket_name}"
}

# ── For Kinesis Firehose destination ──────────────────────────────────────────
output "bucket_arn_with_prefix" {
  description = "Bucket ARN with wildcard suffix — use in IAM policies for Firehose."
  value       = "${aws_s3_bucket.this.arn}/*"
}
