# modules/database/dynamodb/main.tf
#
# Central Log persistence tier: the five DynamoDB tables of CL-LLD-DAT-01
# (§5 and §10.1), hardened to the platform three-tier contract.
#
# What this module creates:
#   1. {prefix}-logs          — transactional audit log, PK pk / SK sk, NO GSI
#   2. {prefix}-log-payloads  — 1:1 hot payload cache, PK lid
#   3. {prefix}-applications  — producer catalog, PK app, GSI gsi-app-state
#   4. {prefix}-services      — service catalog, PK app / SK svc, GSI gsi-svc-state
#   5. {prefix}-wait-logs     — deferred logs, PK pk / SK sk, sparse GSI gsi-wait-pending
#   6. Application Auto Scaling on the logs table (PROVISIONED mode only)
#
# What this module does NOT create:
#   - KMS keys                     → account baseline (discovered by alias)
#   - The analytics path (Glue, Firehose, Athena) → separate module, out of scope
#   - OpenSearch                   → NOT BUILT (CL-LLD-DAT-02); Streams stay on
#                                    so the capability can be reactivated
#   - IAM roles for the Lambdas    → modules/identity/irsa-role or the app repo
#   - CloudWatch alarms            → §8.5 lists the recommended set; not in this
#                                    module's file contract yet
#
# Hardening baked in (not configurable off):
#   - SSE-KMS with a customer-managed CMK on all five tables
#   - The five-table catalog and every key schema
#   - Streams (NEW_IMAGE) on logs, applications and services
#   - prevent_destroy on logs
#   - TTL enabled on logs, log-payloads and wait-logs

# -----------------------------------------------------------------------------
# 1. logs — transactional audit log store
#
#   PK  pk = "C#<token(client_id)>#<hw_date yyyyMMdd>"
#   SK  sk = "<trx_date ISO-8601 UTC ms>#<log_id>"
#
# NO SECONDARY INDEXES. The screen's query is by client and date and is served
# by a single Query on pk plus an sk range (CL-LLD-DAT-01 §5.1.3). Each GSI would
# replicate all 10M daily writes: the three indexes of the earlier design cost
# more than the table itself and none served a confirmed access pattern.
#
# Only pk and sk are declared: DynamoDB rejects any AttributeDefinition that does
# not participate in a key schema, so declaring client_id or hw_date — which are
# COMPONENTS INSIDE pk, not attributes — would fail the deployment.
#
# FUTURE (do not add without a decision): gsi-seq (HASH seq, RANGE ts, projection
# INCLUDE) would let Fraud/Audit start an investigation from a transaction number
# when the client is unknown. It costs ~USD 110/month and no confirmed screen
# consumes it — CL-LLD-DAT-01 §5.1.3 and §12.2 #5 recommend deciding it with
# evidence of real use. A GSI can be added to an existing table later without
# reprocessing history, so leaving it out now is reversible.
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "logs" {
  name         = local.table_names.logs
  billing_mode = var.billing_mode
  hash_key     = "pk"
  range_key    = "sk"

  read_capacity  = local.read_capacity
  write_capacity = local.write_capacity

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # 🔒 LOCKED — TTL is the ONLY deletion path for an audit record: no execution
  # role holds DeleteItem on this table (§9.3). The attribute name is FREE; the
  # platform default is 'exp' (§7.2).
  ttl {
    attribute_name = var.ttl_attribute_name
    enabled        = true
  }

  # 🔒 LOCKED — feeds the S3 analytics archive and keeps the door open to
  # reactivating search. NEW_IMAGE is enough: no consumer needs the prior value.
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  point_in_time_recovery {
    enabled = local.point_in_time_recovery
  }

  # 🔒 LOCKED — customer-managed key, never the AWS-owned default (§9.1).
  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  deletion_protection_enabled = local.deletion_protection

  tags = merge(local.tags, {
    Name    = local.table_names.logs
    Purpose = "log-primary-store"
  })

  lifecycle {
    # 🔒 LOCKED — a DynamoDB primary key cannot be modified after creation. Any
    # change to hash_key or range_key forces Terraform to recreate the table and,
    # with it, to destroy already-ingested evidence. The plan must fail instead.
    prevent_destroy = true

    # In PROVISIONED mode Application Auto Scaling owns the live capacity of this
    # table. Without this, every plan after a scaling event would show a diff and
    # every apply would fight the scaling policy back down to the baseline. The
    # baseline still has effect: it is the min_capacity of the scalable target
    # below, which IS tracked by Terraform. In PAY_PER_REQUEST mode both values
    # are null and there is nothing to ignore.
    ignore_changes = [read_capacity, write_capacity]

    # 🛡️ The Auto Scaling minimum cannot exceed the (clamped) maximum, or the
    # scalable target is rejected at apply time with an opaque API error.
    precondition {
      condition     = !local.is_provisioned || var.write_capacity <= local.write_capacity_max
      error_message = "write_capacity (${var.write_capacity}) exceeds the effective Auto Scaling maximum (${local.write_capacity_max}) for ambiente=${var.ambiente}. The per-environment WCU ceiling is ${local.write_capacity_ceiling}."
    }

    precondition {
      condition     = !local.is_provisioned || var.read_capacity <= local.read_capacity_max
      error_message = "read_capacity (${var.read_capacity}) exceeds the effective Auto Scaling maximum (${local.read_capacity_max}) for ambiente=${var.ambiente}. The per-environment RCU ceiling is ${local.read_capacity_ceiling}."
    }
  }

  depends_on = [terraform_data.guards]
}

# -----------------------------------------------------------------------------
# Auto Scaling on the logs table — PROVISIONED mode only
#
# Target-tracking at 70% utilisation (CL-LLD-DAT-01 §8.2). Write throttling on
# this table means potential LOSS OF AUDIT RECORDS (§8.5), so the write target is
# not optional once capacity is provisioned.
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_target" "logs_write" {
  count = local.logs_autoscaling ? 1 : 0

  max_capacity       = local.write_capacity_max
  min_capacity       = var.write_capacity
  resource_id        = "table/${aws_dynamodb_table.logs.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "logs_write" {
  count = local.logs_autoscaling ? 1 : 0

  name               = "${local.table_names.logs}-write-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.logs_write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.logs_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.logs_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.autoscaling_target_utilization

    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
  }
}

resource "aws_appautoscaling_target" "logs_read" {
  count = local.logs_autoscaling ? 1 : 0

  max_capacity       = local.read_capacity_max
  min_capacity       = var.read_capacity
  resource_id        = "table/${aws_dynamodb_table.logs.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "logs_read" {
  count = local.logs_autoscaling ? 1 : 0

  name               = "${local.table_names.logs}-read-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.logs_read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.logs_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.logs_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.autoscaling_target_utilization

    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
  }
}

# -----------------------------------------------------------------------------
# 2. log-payloads — hot payload copy, 1:1 with the logs table
#
#   PK  lid = log_id
#
# No sort key: the relationship is strictly 1:1, exactly like the shared key of
# gldata in the source model (CL-LLD-DAT-01 §5.2).
#
# The CANONICAL payload copy always lives in S3, grouped into objects of ~200
# payloads. This table is an optional read cache, not the source of truth — the
# design document classifies it as "en suspenso" because no confirmed screen
# consumes a payload. It is built here because the five-table catalog is LOCKED;
# leaving it empty costs storage only.
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "payloads" {
  name         = local.table_names.payloads
  billing_mode = var.billing_mode
  hash_key     = "lid"

  read_capacity  = local.read_capacity
  write_capacity = local.write_capacity

  attribute {
    name = "lid"
    type = "S"
  }

  ttl {
    attribute_name = var.ttl_attribute_name
    enabled        = true
  }

  point_in_time_recovery {
    enabled = local.point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  deletion_protection_enabled = local.deletion_protection

  tags = merge(local.tags, {
    Name    = local.table_names.payloads
    Purpose = "log-payloads"
  })

  depends_on = [terraform_data.guards]
}

# -----------------------------------------------------------------------------
# 3. applications — producer application catalog
#
#   PK  app = application_code
#   GSI gsi-app-state: HASH st (state A | I | T), projection ALL
#
# Permanent master data: no TTL, deletion protection on, PITR on. Volumetry of
# tens of items, so the index cost is negligible (CL-LLD-DAT-01 §5.4).
# Always PAY_PER_REQUEST — provisioning capacity for < 1 WCU/s costs more than
# it saves.
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "applications" {
  name         = local.table_names.applications
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "app"

  attribute {
    name = "app"
    type = "S"
  }

  attribute {
    name = "st"
    type = "S"
  }

  global_secondary_index {
    name            = "gsi-app-state"
    hash_key        = "st"
    projection_type = "ALL"
  }

  # 🔒 LOCKED — invalidates the catalog cache the Lambdas hold in memory, the
  # cloud-native equivalent of the InitialDataServicesEvent CDI event (§7.3).
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  point_in_time_recovery {
    enabled = local.point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  deletion_protection_enabled = local.deletion_protection

  tags = merge(local.tags, {
    Name    = local.table_names.applications
    Purpose = "catalogo"
  })

  depends_on = [terraform_data.guards]
}

# -----------------------------------------------------------------------------
# 4. services — services per application
#
#   PK  app = application_code
#   SK  svc = service_code
#   GSI gsi-svc-state: HASH st, RANGE asv ("<app>#<svc>"), projection ALL
#
# The key order inverts GlservicePK, which declares serviceCode first. The real
# access pattern is "all services of an application" — what ServiceDao.searchAll()
# does with its left join fetch — and putting app first resolves it with a Query
# instead of a Scan (CL-LLD-DAT-01 §5.5).
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "services" {
  name         = local.table_names.services
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "app"
  range_key    = "svc"

  attribute {
    name = "app"
    type = "S"
  }

  attribute {
    name = "svc"
    type = "S"
  }

  attribute {
    name = "st"
    type = "S"
  }

  # Materialised "<app>#<svc>" attribute: a GSI sort key must be a single
  # attribute, so the application writes the composed value when it persists the
  # service. Same device pk and sk use on the logs table.
  attribute {
    name = "asv"
    type = "S"
  }

  # Resolves searchServicesByState(COD_ACTIVE) with a Query, instead of the Scan
  # that state as a non-indexed attribute would require.
  global_secondary_index {
    name            = "gsi-svc-state"
    hash_key        = "st"
    range_key       = "asv"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  point_in_time_recovery {
    enabled = local.point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  deletion_protection_enabled = local.deletion_protection

  tags = merge(local.tags, {
    Name    = local.table_names.services
    Purpose = "catalogo"
  })

  depends_on = [terraform_data.guards]
}

# -----------------------------------------------------------------------------
# 5. wait-logs — deferred logs (Glwaitlog + GlwaitData consolidated)
#
#   PK  pk  = "W#<application_code>#<service_code>"
#   SK  sk  = "<trx_date ISO>#<wait_id>"
#   GSI gsi-wait-pending: HASH pnd ("<app>#<svc>"), RANGE ts   -- SPARSE
#
# The earlier schema (message_group_id / sequence_number) modelled a FIFO SQS
# queue, not the domain entity. The messaging queue is STANDARD SQS and lives in
# modules/messaging/sqs (CL-LLD-ARQ-03): this table persists the logs waiting for
# their application or service to become active, which is a different thing.
#
# The partition key groups by the (application, service) pair, which is exactly
# the unit the release batch operates on (CL-LLD-DAT-01 §5.3).
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "wait_logs" {
  name         = local.table_names.wait_logs
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # Sparse-index attribute. Written when the log is enqueued and REMOVEd when it
  # is released, so the item leaves the index on its own.
  attribute {
    name = "pnd"
    type = "S"
  }

  attribute {
    name = "ts"
    type = "S"
  }

  # SPARSE index: by construction it contains only the pending logs, with no
  # filter and no scan. It replaces the earlier gsi-status, whose partition key
  # had two possible values (PEN / REL) and guaranteed a hot partition.
  global_secondary_index {
    name            = "gsi-wait-pending"
    hash_key        = "pnd"
    range_key       = "ts"
    projection_type = "ALL"
  }

  # TTL of 7 days AFTER release (§5.3.2) — the writer computes the value.
  ttl {
    attribute_name = var.ttl_attribute_name
    enabled        = true
  }

  point_in_time_recovery {
    enabled = local.point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  deletion_protection_enabled = local.deletion_protection

  tags = merge(local.tags, {
    Name    = local.table_names.wait_logs
    Purpose = "wait-queue"
  })

  depends_on = [terraform_data.guards]
}
