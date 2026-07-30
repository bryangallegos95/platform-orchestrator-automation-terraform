# modules/messaging/sqs/locals.tf
#
# Centralised naming convention, HARDENING CONTRACT and tag factory.
#
# HARDENING CONTRACT:
#   LOCKED     — SSE-KMS with CMK (never aws/sqs), deny non-TLS queue policy,
#                deny non-owner-account access, DLQ always created.
#   GUARD-RAIL — message_retention floor (4 days), dlq_max_receive_count floor (3),
#                dlq_retention floor (7 days).
#   FREE       — visibility timeout, delay, FIFO, deduplication, message size,
#                receive wait time, extra tags.
#
# Naming pattern:
#   Queue      : sqs-aw-{region_short}-{service}-{workload}-{queue_key}-{ambiente}
#   DLQ        : sqs-aw-{region_short}-{service}-{workload}-{queue_key}-dlq-{ambiente}
#   FIFO queues get .fifo suffix appended automatically.

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Environment posture ───────────────────────────────────────────────────
  is_prod_like = contains(["preprod", "prod", "dr"], var.ambiente)

  # ── KMS resolution ────────────────────────────────────────────────────────
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.sqs[0].target_key_arn

  # ── GUARD-RAIL floors ─────────────────────────────────────────────────────
  # Message retention: floor 4 days (son repo may raise to 14, never below 4)
  message_retention_floor = 4

  # DLQ max receive count: floor 3 (son repo may raise, never below 3)
  dlq_max_receive_count_floor = 3

  # DLQ retention: floor 7 days (son repo may raise to 14, never below 7)
  dlq_retention_floor = 7

  # ── Queue configuration with guard-rail enforcement ───────────────────────
  queues = {
    for k, v in var.queues : k => {
      fifo                        = v.fifo
      visibility_timeout_seconds  = v.visibility_timeout_seconds
      message_retention_seconds   = max(local.message_retention_floor, v.message_retention_days) * 86400
      max_message_size            = v.max_message_size_bytes
      delay_seconds               = v.delay_seconds
      receive_wait_time_seconds   = v.receive_wait_time_seconds
      content_based_deduplication = v.fifo ? v.content_based_deduplication : false
      dlq_max_receive_count       = max(local.dlq_max_receive_count_floor, v.dlq_max_receive_count)
      dlq_retention_seconds       = max(local.dlq_retention_floor, v.dlq_message_retention_days) * 86400
      # Names
      queue_name = v.fifo ? "sqs-aw-${local.region_short}-${var.service}-${var.workload}-${k}-${var.ambiente}.fifo" : "sqs-aw-${local.region_short}-${var.service}-${var.workload}-${k}-${var.ambiente}"
      dlq_name   = v.fifo ? "sqs-aw-${local.region_short}-${var.service}-${var.workload}-${k}-dlq-${var.ambiente}.fifo" : "sqs-aw-${local.region_short}-${var.service}-${var.workload}-${k}-dlq-${var.ambiente}"
    }
  }

  # ── Tag factory ─────────────────────────────────────────────────────────
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
    Ambiente           = var.ambiente
    ManagedBy          = "terraform"
  }

  tags = merge(local.mandatory_tags, var.extra_tags)
}
