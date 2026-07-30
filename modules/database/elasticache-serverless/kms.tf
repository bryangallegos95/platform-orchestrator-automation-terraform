# modules/database/elasticache-serverless/kms.tf
#
# Additive KMS grants for consumer workload roles (IRSA roles, Lambda, etc.)
# that need to interact with the encrypted cache.
#
# NOTE: For ElastiCache Serverless with IAM auth, the consumer roles primarily
# need `elasticache:Connect` permission (handled by the IRSA module). The KMS
# grant is for roles that need direct key access (e.g. snapshot export/import,
# data migration scripts). Same pattern as aurora-postgresql/kms.tf.

resource "aws_kms_grant" "consumers" {
  for_each = var.kms_consumer_role_arns

  name              = "${local.cache_name}-${each.key}"
  key_id            = local.kms_key_arn
  grantee_principal = each.value

  operations = [
    "Encrypt",
    "Decrypt",
    "GenerateDataKey",
    "DescribeKey",
  ]
}
