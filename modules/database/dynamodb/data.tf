# modules/database/dynamodb/data.tf
#
# KMS discovery by alias. Same pattern as aurora-postgresql/data.tf and
# messaging/sqs/data.tf — the module NEVER creates keys; the CMK is part of the
# account baseline.
#
# KMS contract:
#   DynamoDB tables at rest : alias/DynamoDB  (var.kms_key_alias)
#   Pass kms_key_arn to bypass alias discovery.
#
# DynamoDB is a regional managed service: there is NO VPC, subnet or security
# group discovery here (contrast with aurora-postgresql / elasticache-serverless).

data "aws_caller_identity" "current" {}

# Active region — cross-checked against var.aws_region by the guards.
data "aws_region" "current" {}

# Pre-existing account DynamoDB CMK, resolved by alias unless an explicit ARN is
# supplied. CL-LLD-DAT-01 §9.1 requires a customer-managed key: the AWS-owned
# default key is NOT acceptable for transactional audit evidence.
data "aws_kms_alias" "dynamodb" {
  count = var.kms_key_arn == "" ? 1 : 0

  name = var.kms_key_alias
}
