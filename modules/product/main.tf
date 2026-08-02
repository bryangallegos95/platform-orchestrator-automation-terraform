# modules/product/main.tf
#
# Product compositor — Layer 2 in the Building Blocks Model.
# Composes standalone building blocks (Layer 1) into a single Terraform state
# per environment. Resolves native dependencies between blocks via module
# outputs → inputs (no remote_state, no data sources for cross-block refs).
#
# Each building block performs its OWN VPC/KMS discovery internally.
# This file only defines shared locals for the compositor's own logic
# (policy generation, tag factory, naming helpers).
#
# The compositor does NOT create any AWS resources directly — it only
# orchestrates child modules.

locals {
  # ── Region-derived values (for policy ARN construction) ──────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Environment posture ───────────────────────────────────────────────────
  is_prod_like = contains(["preprod", "prod", "dr"], var.ambiente)

  # ── Common identity variables passed to all building blocks ──────────────
  common_vars = {
    aws_region          = var.aws_region
    service             = var.service
    workload            = var.workload
    funcionalidad       = var.funcionalidad
    ambiente            = var.ambiente
    aws_account_id      = var.aws_account_id
    aplicacion          = var.aplicacion
    propietario_recurso = var.propietario_recurso
    producto            = var.producto
    centro_costo        = var.centro_costo
    extra_tags          = var.extra_tags
  }

  # ── IRSA policy generation helpers ────────────────────────────────────────
  # These build IAM policy JSON documents for IRSA roles that need access
  # to other building blocks. Only computed when the dependent block exists.

  # Aurora: rds-db:connect policy (IAM database authentication)
  # Includes KMS decrypt for the RDS CMK (needed for IAM DB auth token generation)
  aurora_connect_policy = var.aurora_enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AuroraIAMConnect"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = ["${module.aurora[0].iam_auth_resource_arn_prefix}/*"]
      },
      {
        Sid      = "AuroraKMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.aurora[0].kms_key_arn]
      },
    ]
  }) : ""

  # SQS: full access policy (send + receive + delete + get attributes)
  # Includes KMS encrypt/decrypt for the SQS CMK (messages are CMK-encrypted)
  sqs_full_policy = var.sqs_enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSFullAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = concat(
          values(module.sqs[0].queue_arns),
          values(module.sqs[0].dlq_arns),
        )
      },
      {
        Sid    = "SQSKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = [module.sqs[0].kms_key_arn]
      },
    ]
  }) : ""

  # Redis: elasticache:Connect policy (IAM authentication for Serverless)
  # Includes KMS decrypt for the ElastiCache CMK
  redis_connect_policy = var.redis_enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ElastiCacheConnect"
        Effect = "Allow"
        Action = ["elasticache:Connect"]
        Resource = [
          module.redis[0].cache_arn,
          "${module.redis[0].cache_arn}/*",
        ]
      },
      {
        Sid      = "ElastiCacheKMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.redis[0].kms_key_arn]
      },
    ]
  }) : ""
}
