# modules/messaging/sqs/kms.tf
#
# Additive KMS grants for consumer workload roles (IRSA roles, Lambda, etc.)
# that need to encrypt/decrypt SQS messages via the account's SQS CMK.
#
# Same pattern as aurora-postgresql/kms.tf — does NOT modify the key policy.

resource "aws_kms_grant" "consumers" {
  for_each = var.kms_consumer_role_arns

  name              = "sqs-aw-${local.region_short}-${var.service}-${var.workload}-${each.key}-${var.ambiente}"
  key_id            = local.kms_key_arn
  grantee_principal = each.value

  operations = [
    "Encrypt",
    "Decrypt",
    "GenerateDataKey",
    "DescribeKey",
  ]
}
