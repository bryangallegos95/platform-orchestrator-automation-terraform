# modules/database/dynamodb/main.tf
#
# DynamoDB table set for the "Central Log" platform.
# One module call = the full 6-table set (they are a single logical data model,
# not independent building blocks).
#
# What this module creates:
#   1. 6 DynamoDB tables (catálogo en locals.tf)
#   2. 4 GSIs on the `logs` table
#   3. A DynamoDB Stream on `wait-logs` (consumed by the `wait-processor` Lambda)
#   4. Additive KMS grants for consumer workload roles
#
# What this module does NOT create:
#   - KMS keys                 -> account baseline (discovered by alias)
#   - IAM roles for consumers  -> modules/identity/irsa-role
#   - Lambda event source mappings for the stream -> consumer repo
#   - VPC / subnets / SGs      -> N/A, DynamoDB is a regional VPC-less service
#
# Hardening baked in (not configurable off):
#   - At-rest encryption: CMK (account's existing DynamoDB CMK, never AWS-managed)
#   - Point-in-Time Recovery: always enabled
#   - Table catalog and key schema: fixed in locals.tf
#
# Escrito SIN acceso a `platform-knowledge-base`. Los `# TODO: validar contra
#    platform-knowledge-base` marcan PROPUESTAS pendientes de confirmar.


# ── DynamoDB tables ───────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "this" {
  for_each = local.tables

  name         = local.table_names[each.key]
  billing_mode = var.billing_mode
  table_class  = var.table_class

  # ── Key schema — LOCKED ───────────────────────────────────────────────
  hash_key  = each.value.hash_key
  range_key = each.value.range_key

  dynamic "attribute" {
    for_each = each.value.attributes
    content {
      name = attribute.key
      type = attribute.value
    }
  }

  # ── Capacity — solo con PROVISIONED (null con PAY_PER_REQUEST) ───────────
  read_capacity  = local.read_capacity
  write_capacity = local.write_capacity

  # ── Global Secondary Indexes ─────────────────────────────────────────────
  # Solo `logs` los declara hoy (ver local.gsis).
  #
  # NOTA: el provider AWS 6.x marca `hash_key`/`range_key` del GSI como
  # deprecados en favor de un bloque `key_schema`, que NO existe en 5.x. Como
  # versions.tf declara `>= 5.0` (igual que el resto de módulos del repo), se
  # mantiene la forma portable. Migrar cuando el repo suba el piso a 6.x.
  dynamic "global_secondary_index" {
    for_each = try(local.gsis[each.key], {})
    content {
      name            = global_secondary_index.key
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = var.gsi_projection_type
      read_capacity   = local.read_capacity
      write_capacity  = local.write_capacity
    }
  }

  # ── TTL — `logs` / `wait-logs` + espejo en sus tablas de payloads ────────
  # DynamoDB expira por epoch escrito en el atributo por la aplicación; los
  # días de retención se exponen como output para el productor de ítems.
  ttl {
    enabled        = each.value.ttl_enabled
    attribute_name = each.value.ttl_enabled ? var.ttl_attribute_name : ""
  }

  # ── Streams — habilitado solo en `wait-logs` ─────────────────────────────
  stream_enabled   = each.value.stream_view_type != null
  stream_view_type = each.value.stream_view_type

  # ── Encryption — LOCKED ───────────────────────────────────────────────
  # CMK de cuenta descubierta por alias. NUNCA la clave AWS-managed
  # (`alias/aws/dynamodb`), que es lo que aplica DynamoDB si se omite el bloque.
  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  # ── Point-in-Time Recovery — LOCKED (PROPUESTO) ───────────────────────
  # TODO: validar contra platform-knowledge-base — se propone LOCKED (siempre
  # ON, sin variable, según la regla "no añadir variables para settings LOCKED"
  # de AGENTS.md). Si el baseline lo define como GUARD-RAIL por ambiente, pasa
  # a variable con piso.
  point_in_time_recovery {
    enabled = true
  }

  # ── GUARD-RAIL — Deletion protection ────────────────────────────────
  deletion_protection_enabled = local.deletion_protection_enabled

  tags = merge(local.tags, { Name = local.table_names[each.key] })

  depends_on = [terraform_data.guards]

  lifecycle {
    # Capacity coherente con el billing mode elegido.
    precondition {
      condition     = !local.is_provisioned || (var.provisioned_read_capacity != null && var.provisioned_write_capacity != null)
      error_message = "billing_mode=PROVISIONED requires both provisioned_read_capacity and provisioned_write_capacity."
    }

    precondition {
      condition     = local.is_provisioned || (var.provisioned_read_capacity == null && var.provisioned_write_capacity == null)
      error_message = "provisioned_read_capacity/provisioned_write_capacity only apply with billing_mode=PROVISIONED. Leave them null with PAY_PER_REQUEST."
    }

    # GUARD-RAIL: la deletion protection no se puede bajar en prod-like.
    precondition {
      condition     = !local.deletion_protection_floor || local.deletion_protection_enabled
      error_message = "deletion_protection_enabled cannot be disabled in ${var.ambiente} (prod-like floor is ON)."
    }
  }
}

# ── KMS grants for consumer workload roles ────────────────────────────────────
# Mismo patrón que aurora-postgresql/kms.tf y elasticache-serverless/kms.tf:
# el módulo no crea llaves, solo concede uso aditivo de la CMK descubierta.
# Un único grant por rol cubre las 6 tablas (el grant es sobre la llave).
resource "aws_kms_grant" "consumers" {
  for_each = var.kms_consumer_role_arns

  name              = "${local.resource_prefix}-${var.ambiente}-${each.key}"
  key_id            = local.kms_key_arn
  grantee_principal = each.value

  operations = [
    "Encrypt",
    "Decrypt",
    "GenerateDataKey",
    "DescribeKey",
  ]
}
