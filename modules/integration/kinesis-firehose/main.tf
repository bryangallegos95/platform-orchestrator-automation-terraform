# modules/integration/kinesis-firehose/main.tf
#
# Kinesis Data Firehose Delivery Stream — Direct PUT → S3 (Parquet).
#
# What this module creates:
#   1. Firehose delivery stream (Direct PUT source → S3 destination)
#   2. Format conversion: JSON → Apache Parquet (via Glue schema)
#   3. IAM role for delivery (see iam.tf)
#   4. CloudWatch Log Group + Stream for error logging
#
# What this module does NOT create:
#   - S3 bucket (input: destination_bucket_arn from s3-private module)
#   - KMS key (input: kms_key_arn from s3-private module)
#   - Glue Database/Table (must be created separately or by AppFlow)
#   - Source application (AppFlow module pushes via Direct PUT)

# ══════════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ══════════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}

# ══════════════════════════════════════════════════════════════════════════════
# ACCOUNT GUARDRAIL
# ══════════════════════════════════════════════════════════════════════════════

resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id})."
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# CLOUDWATCH LOG GROUP (for Firehose error logging)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_cloudwatch_log_group" "firehose" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = local.log_group_name })
}

resource "aws_cloudwatch_log_stream" "s3_delivery" {
  name           = local.log_stream_name
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# ══════════════════════════════════════════════════════════════════════════════
# KINESIS DATA FIREHOSE DELIVERY STREAM
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = local.stream_name
  destination = "extended_s3"

  # ── Server-Side Encryption at rest (Infracost/CIS recommendation) ─────────
  server_side_encryption {
    enabled  = true
    key_type = "AWS_OWNED_CMK"
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = var.destination_bucket_arn

    # ── S3 key prefixes ─────────────────────────────────────────────────────
    prefix              = var.s3_prefix
    error_output_prefix = var.s3_error_prefix

    # ── Buffering ───────────────────────────────────────────────────────────
    buffering_interval = var.buffering_interval_seconds
    buffering_size     = var.buffering_size_mb

    # ── Encryption (SSE-KMS — same key as the bucket) ───────────────────────
    kms_key_arn = var.kms_key_arn

    # ── CloudWatch error logging ────────────────────────────────────────────
    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.s3_delivery.name
    }

    # ── Format conversion (JSON → Parquet) ──────────────────────────────────
    dynamic "data_format_conversion_configuration" {
      for_each = var.output_format != "DISABLED" ? [1] : []
      content {
        enabled = true

        input_format_configuration {
          deserializer {
            open_x_json_ser_de {}
          }
        }

        output_format_configuration {
          serializer {
            dynamic "parquet_ser_de" {
              for_each = var.output_format == "PARQUET" ? [1] : []
              content {
                compression = var.parquet_compression
              }
            }
            dynamic "orc_ser_de" {
              for_each = var.output_format == "ORC" ? [1] : []
              content {
                compression = "SNAPPY"
              }
            }
          }
        }

        schema_configuration {
          database_name = var.schema_database_name
          table_name    = var.schema_table_name
          region        = local.schema_region
          role_arn      = var.schema_role_arn != "" ? var.schema_role_arn : aws_iam_role.firehose.arn
        }
      }
    }
  }

  tags = merge(local.tags, { Name = local.stream_name })

  depends_on = [
    terraform_data.account_guard,
    aws_iam_role_policy.s3_delivery,
    aws_iam_role_policy.cloudwatch
  ]
}
