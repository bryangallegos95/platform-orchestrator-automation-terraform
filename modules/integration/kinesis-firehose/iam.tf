# modules/integration/kinesis-firehose/iam.tf
#
# IAM Role for Kinesis Data Firehose delivery.
# Grants permissions to:
#   - Write objects to the destination S3 bucket
#   - Use the KMS key for server-side encryption
#   - Write error logs to CloudWatch
#   - Access Glue Catalog for schema (format conversion)

# ── Firehose Delivery Role ────────────────────────────────────────────────────

resource "aws_iam_role" "firehose" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.aws_account_id
        }
      }
    }]
  })

  tags = local.tags
}

# ── S3 Delivery Policy ────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "s3_delivery" {
  name = "firehose-s3-delivery"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          var.destination_bucket_arn,
          "${var.destination_bucket_arn}/*"
        ]
      },
      {
        Sid    = "KMSEncryption"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [var.kms_key_arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = [
              var.destination_bucket_arn,
              "${var.destination_bucket_arn}/*"
            ]
          }
        }
      }
    ]
  })
}

# ── CloudWatch Logging Policy ─────────────────────────────────────────────────

resource "aws_iam_role_policy" "cloudwatch" {
  name = "firehose-cloudwatch-logs"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = [
        "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:${local.log_group_name}:*"
      ]
    }]
  })
}

# ── Glue Catalog Policy (for format conversion) ──────────────────────────────

resource "aws_iam_role_policy" "glue" {
  count = var.output_format != "DISABLED" ? 1 : 0
  name  = "firehose-glue-access"
  role  = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "glue:GetTable",
        "glue:GetTableVersion",
        "glue:GetTableVersions",
        "glue:GetDatabase"
      ]
      Resource = [
        "arn:aws:glue:${local.schema_region}:${var.aws_account_id}:catalog",
        "arn:aws:glue:${local.schema_region}:${var.aws_account_id}:database/${var.schema_database_name}",
        "arn:aws:glue:${local.schema_region}:${var.aws_account_id}:table/${var.schema_database_name}/${var.schema_table_name}"
      ]
    }]
  })
}
