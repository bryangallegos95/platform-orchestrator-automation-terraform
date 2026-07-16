# modules/integration/appflow/iam.tf
#
# IAM Role for AWS AppFlow.
# Grants permissions to:
#   - Write records to Kinesis Data Firehose delivery stream
#   - Access source connector (via AppFlow managed permissions)

# ── AppFlow Service Role ──────────────────────────────────────────────────────

resource "aws_iam_role" "appflow" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "appflow.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.aws_account_id
        }
      }
    }]
  })

  tags = local.tags
}

# ── Firehose Delivery Policy ─────────────────────────────────────────────────
# AppFlow needs to PutRecord/PutRecordBatch to the Firehose stream.

resource "aws_iam_role_policy" "firehose_delivery" {
  name = "appflow-firehose-delivery"
  role = aws_iam_role.appflow.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "FirehoseAccess"
      Effect = "Allow"
      Action = [
        "firehose:PutRecord",
        "firehose:PutRecordBatch",
        "firehose:DescribeDeliveryStream"
      ]
      Resource = [var.destination_firehose_arn]
    }]
  })
}
