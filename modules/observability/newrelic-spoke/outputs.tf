# modules/observability/newrelic-spoke/outputs.tf

output "subscription_filter_arns" {
  description = "Map of sanitized log group key to subscription filter ARN."
  value       = { for k, v in aws_cloudwatch_log_subscription_filter.to_hub : k => v.arn }
}

output "iam_role_arn" {
  description = "ARN of the IAM role assumed by CloudWatch Logs to write to the hub destination."
  value       = aws_iam_role.cw_to_destination.arn
}
