# modules/messaging/sqs/main.tf
#
# SQS queues with mandatory DLQ, CMK encryption, and hardened queue policies.
# One module call = N queues (map-driven). Each queue always gets a DLQ.
#
# What this module creates (per queue):
#   1. Main SQS queue (Standard or FIFO) encrypted with account CMK
#   2. Dead Letter Queue (DLQ) encrypted with same CMK
#   3. Redrive policy linking main queue → DLQ
#   4. Queue resource policies (deny non-TLS, deny non-owner account)
#   5. Additive KMS grants for consumer workload roles
#
# What this module does NOT create:
#   - KMS keys                  → account baseline (discovered by alias)
#   - IAM roles for producers   → modules/identity/irsa-role
#   - IAM roles for consumers   → modules/identity/irsa-role
#   - CloudWatch alarms         → son-repo extension or separate observability layer
#
# Hardening baked in (not configurable off):
#   - SSE-KMS with customer-managed CMK (never SQS-managed or unencrypted)
#   - Queue policy: deny non-TLS requests
#   - Queue policy: deny cross-account access
#   - DLQ always created (reliability baseline)
#   - Long-polling enabled by default (receive_wait_time = 20s)

# ── Dead Letter Queues (created FIRST — main queues reference them) ──────────
resource "aws_sqs_queue" "dlq" {
  for_each = local.queues

  name       = each.value.dlq_name
  fifo_queue = each.value.fifo

  # LOCKED — CMK encryption (same key as main queue)
  sqs_managed_sse_enabled           = false
  kms_master_key_id                 = local.kms_key_arn
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds

  # DLQ retention (guard-railed)
  message_retention_seconds = each.value.dlq_retention_seconds

  # DLQ visibility timeout matches main queue (avoids reprocessing storms)
  visibility_timeout_seconds = each.value.visibility_timeout_seconds

  tags = merge(local.tags, {
    Name    = each.value.dlq_name
    QueueOf = each.value.queue_name
    Type    = "DLQ"
  })

  depends_on = [terraform_data.guards]
}

# ── Main Queues ───────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "main" {
  for_each = local.queues

  name       = each.value.queue_name
  fifo_queue = each.value.fifo

  # LOCKED — CMK encryption
  sqs_managed_sse_enabled           = false
  kms_master_key_id                 = local.kms_key_arn
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds

  # Son-repo configurable (within guard-rails)
  visibility_timeout_seconds  = each.value.visibility_timeout_seconds
  message_retention_seconds   = each.value.message_retention_seconds
  max_message_size            = each.value.max_message_size
  delay_seconds               = each.value.delay_seconds
  receive_wait_time_seconds   = each.value.receive_wait_time_seconds
  content_based_deduplication = each.value.content_based_deduplication

  # LOCKED — DLQ always configured (redrive policy)
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.dlq_max_receive_count
  })

  tags = merge(local.tags, {
    Name = each.value.queue_name
    Type = each.value.fifo ? "FIFO" : "Standard"
  })

  depends_on = [terraform_data.guards]
}

# ── Redrive allow policy on DLQ (allows the main queue to send to it) ────────
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each  = local.queues
  queue_url = aws_sqs_queue.dlq[each.key].url

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main[each.key].arn]
  })
}
