# modules/messaging/sqs/policies.tf
#
# Queue resource policies — LOCKED security controls:
#   1. Deny any request that does NOT use TLS (aws:SecureTransport = false)
#   2. Deny any request from a different AWS account (prevent cross-account exfiltration)
#
# These policies are applied to BOTH the main queue AND its DLQ.

# ── Main queue policies ───────────────────────────────────────────────────────
resource "aws_sqs_queue_policy" "main" {
  for_each  = local.queues
  queue_url = aws_sqs_queue.main[each.key].url

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${each.value.queue_name}-policy"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.main[each.key].arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyNonOwnerAccount"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.main[each.key].arn
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid       = "AllowAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.main[each.key].arn
      }
    ]
  })
}

# ── DLQ policies (same controls) ─────────────────────────────────────────────
resource "aws_sqs_queue_policy" "dlq" {
  for_each  = local.queues
  queue_url = aws_sqs_queue.dlq[each.key].url

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${each.value.dlq_name}-policy"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.dlq[each.key].arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyNonOwnerAccount"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.dlq[each.key].arn
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid       = "AllowAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.dlq[each.key].arn
      }
    ]
  })
}
