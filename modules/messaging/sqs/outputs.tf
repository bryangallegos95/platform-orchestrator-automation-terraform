# modules/messaging/sqs/outputs.tf
#
# Outputs for downstream consumers (IRSA module, son-repo references).

output "queue_arns" {
  description = "Map of queue key → ARN for all main queues."
  value       = { for k, q in aws_sqs_queue.main : k => q.arn }
}

output "queue_urls" {
  description = "Map of queue key → URL for all main queues."
  value       = { for k, q in aws_sqs_queue.main : k => q.url }
}

output "queue_names" {
  description = "Map of queue key → name for all main queues."
  value       = { for k, q in aws_sqs_queue.main : k => q.name }
}

output "dlq_arns" {
  description = "Map of queue key → ARN for all DLQs."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.arn }
}

output "dlq_urls" {
  description = "Map of queue key → URL for all DLQs."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.url }
}

output "dlq_names" {
  description = "Map of queue key → name for all DLQs."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.name }
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK used for queue encryption."
  value       = local.kms_key_arn
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────
output "dlq_alarm_arns" {
  description = "Map of queue key → DLQ depth alarm ARN."
  value       = { for k, a in aws_cloudwatch_metric_alarm.dlq_depth : k => a.arn }
}

output "age_alarm_arns" {
  description = "Map of queue key → message age alarm ARN."
  value       = { for k, a in aws_cloudwatch_metric_alarm.queue_age : k => a.arn }
}
