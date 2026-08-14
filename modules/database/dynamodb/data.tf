# modules/database/dynamodb/data.tf
#
# Discovery. DynamoDB is a regional, VPC-less service: unlike
# aurora-postgresql / elasticache-serverless there is NO VPC, subnet or
# Security Group lookup here. The only external dependency is the account's
# pre-existing CMK, discovered by alias — the module NEVER creates KMS keys.

# ── Current identity ──────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── KMS key discovery ─────────────────────────────────────────────────────────
# TODO: validar contra platform-knowledge-base — el alias real de la CMK de
# DynamoDB en el baseline de cuenta es DESCONOCIDO. El default tentativo es
# `alias/DynamoDB` (ver var.kms_alias). Si el baseline expone otro alias
# (p.ej. `alias/DDB`), se cambia SOLO en la variable.
data "aws_kms_alias" "dynamodb" {
  count = var.kms_key_arn == "" ? 1 : 0
  name  = var.kms_alias
}
