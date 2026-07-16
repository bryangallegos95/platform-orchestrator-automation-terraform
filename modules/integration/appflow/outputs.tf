# modules/integration/appflow/outputs.tf
#
# Exposes all identifiers that son-repo stacks or other modules may need.

# ── Flow ──────────────────────────────────────────────────────────────────────
output "flow_name" {
  description = "Name of the AppFlow flow."
  value       = aws_appflow_flow.this.name
}

output "flow_arn" {
  description = "ARN of the AppFlow flow."
  value       = aws_appflow_flow.this.arn
}

output "flow_status" {
  description = "Current status of the AppFlow flow."
  value       = aws_appflow_flow.this.flow_status
}

# ── IAM Role ──────────────────────────────────────────────────────────────────
output "appflow_role_arn" {
  description = "ARN of the IAM role used by AppFlow."
  value       = aws_iam_role.appflow.arn
}

output "appflow_role_name" {
  description = "Name of the IAM role used by AppFlow."
  value       = aws_iam_role.appflow.name
}
