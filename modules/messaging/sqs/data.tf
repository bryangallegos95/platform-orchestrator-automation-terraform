# modules/messaging/sqs/data.tf
#
# KMS key discovery by alias. Same pattern as aurora-postgresql/data.tf.
# The module NEVER creates KMS keys — they are part of the account baseline.

data "aws_kms_alias" "sqs" {
  count = var.kms_key_arn == "" ? 1 : 0
  name  = var.kms_key_alias
}

# Current caller identity — used in guards and queue policies.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
