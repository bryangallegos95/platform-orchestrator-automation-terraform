# modules/identity/irsa-role/outputs.tf
#
# Outputs for downstream consumers:
#   - Kubernetes manifests (ServiceAccount annotation with role ARN)
#   - Other Terraform modules (e.g. SQS KMS grants, Aurora SG rules)
#   - CI/CD pipelines (for validation)

output "role_arns" {
  description = "Map of role key → IAM role ARN. Use these to annotate Kubernetes ServiceAccounts."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "role_names" {
  description = "Map of role key → IAM role name."
  value       = { for k, r in aws_iam_role.this : k => r.name }
}

output "role_ids" {
  description = "Map of role key → IAM role unique ID."
  value       = { for k, r in aws_iam_role.this : k => r.unique_id }
}

output "sa_annotations" {
  description = <<-EOT
    Map of role key → ServiceAccount annotation value for Kubernetes manifests.
    Apply as: metadata.annotations["eks.amazonaws.com/role-arn"] = <value>
    
    Example Kubernetes manifest:
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: bff-sa
        namespace: bff-personas
        annotations:
          eks.amazonaws.com/role-arn: <value from this output>
  EOT
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider used for trust policies."
  value       = local.oidc_provider_arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL used for trust policy conditions."
  value       = local.oidc_issuer_url
}
