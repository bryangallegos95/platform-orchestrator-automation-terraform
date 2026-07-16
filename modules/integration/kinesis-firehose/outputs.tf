# modules/integration/kinesis-firehose/outputs.tf
#
# Exposes all identifiers that son-repo stacks or other modules may need.

# ── Delivery Stream ───────────────────────────────────────────────────────────
output "stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.this.name
}

output "stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.this.arn
}

# ── IAM Role ──────────────────────────────────────────────────────────────────
output "delivery_role_arn" {
  description = "ARN of the IAM role used by Firehose for delivery. Pass to s3-private module's writer_principal_arns."
  value       = aws_iam_role.firehose.arn
}

output "delivery_role_name" {
  description = "Name of the IAM role used by Firehose for delivery."
  value       = aws_iam_role.firehose.name
}

# ── CloudWatch ────────────────────────────────────────────────────────────────
output "log_group_name" {
  description = "CloudWatch Log Group name for Firehose error logs."
  value       = aws_cloudwatch_log_group.firehose.name
}

output "log_group_arn" {
  description = "CloudWatch Log Group ARN for Firehose error logs."
  value       = aws_cloudwatch_log_group.firehose.arn
}
