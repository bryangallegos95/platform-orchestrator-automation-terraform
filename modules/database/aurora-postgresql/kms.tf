# modules/database/aurora-postgresql/kms.tf
#
# Grants consumer workload roles (lambda, ecs, eks, ec2...) permission to USE
# the account's pre-existing RDS CMK. RDS itself uses the key via its key
# policy (account baseline) — these grants are ONLY for workloads that need
# the same key directly (e.g. decrypting cluster snapshots exported to S3, or
# reading Performance Insights data encrypted with it).
#
# NOTE: connecting to the database does NOT require KMS access — storage
# encryption is transparent. Data-plane access control is: Security Group
# (allowed_security_group_ids / allowed_cidrs) + database authentication
# (IAM DB auth or SQL users).
#
# Uses aws_kms_grant (additive) — does NOT manage/overwrite the key policy, so
# it coexists with existing key-policy statements (admins, ViaService, etc.).
# Same pattern as modules/openshift/rosa-hcp/kms.tf.

resource "aws_kms_grant" "consumers" {
  for_each = var.kms_consumer_role_arns

  name              = "${local.cluster_name}-${each.key}"
  key_id            = local.kms_key_arn
  grantee_principal = each.value

  operations = [
    "Encrypt",
    "Decrypt",
    "ReEncryptFrom",
    "ReEncryptTo",
    "GenerateDataKey",
    "GenerateDataKeyWithoutPlaintext",
    "DescribeKey",
  ]
}
