# modules/database/dynamodb/locals.tf
#
# Centralised naming convention, TABLE CATALOG, HARDENING CONTRACT and tag factory.
#
# HARDENING CONTRACT (BORRADOR — ver README, tabla de 3 capas):
#   LOCKED     — SSE con CMK de cuenta (nunca clave AWS-managed),
#                Point-in-Time Recovery siempre habilitado,
#                catálogo de tablas + key schema (definido aquí, no overridable).
#   GUARD-RAIL — deletion protection (piso ON en prod-like),
#                retención TTL (piso por ambiente).
#   FREE       — billing mode y capacities, table class, proyección de GSI,
#                nombre del atributo TTL, retención por encima del piso, tags.
#
# Naming pattern (PROPUESTO — análogo a `rds-aw-...` de aurora-postgresql):
#   Tabla : ddb-aw-{region_short}-{workload}-{funcionalidad}-{tabla}-{ambiente}
#
# TODO: validar contra platform-knowledge-base — el prefijo `ddb`, el orden de
# los segmentos y la inclusión de {funcionalidad} son PROPUESTA. Todo el naming
# se deriva de `local.resource_prefix`: cambiarlo es un cambio de UNA línea.

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Environment posture ───────────────────────────────────────────────────
  is_prod_like = contains(["preprod", "prod", "dr"], var.ambiente)

  # ── Composed naming ──────────────────────────────────────────────────────
  # Pattern: {tipo}-aw-{region}-{workload}-{funcionalidad}-{tabla}-{ambiente}
  resource_prefix = "ddb-aw-${local.region_short}-${var.workload}-${var.funcionalidad}"

  table_names = {
    for key, cfg in local.tables_raw : key => "${local.resource_prefix}-${key}-${var.ambiente}"
  }

  # ── Atributo de estado del GSI 3 de `logs` ───────────────────────────────
  # DISCREPANCIA EN LA FUENTE: el análisis de Central Log lista el atributo
  # de la tabla `logs` como `estado` (español, igual que en `applications`,
  # `services` y `wait-logs`) pero nombra el GSI 3 sobre `status` (inglés).
  # Se asume `estado` por consistencia con el resto del modelo. Se define UNA
  # sola vez: si la fuente de verdad dice `status`, se cambia aquí.
  # TODO: validar contra platform-knowledge-base / equipo de Central Log.
  # OJO: cambiar la key de un GSI ya creado obliga a recrear el índice.
  logs_status_attribute = "estado"

  # ── TTL espejo en las tablas de payloads ─────────────────────────────────
  # `log-payloads` y `wait-payloads` son 1:1 con `logs` y `wait-logs` (misma
  # key: id_log / id_wait_log), que SÍ expiran por TTL. Sin TTL espejo, al
  # expirar el log padre su payload queda huérfano para siempre: la tabla que
  # se separó justamente para aliviar el tamaño de `logs` crece sin control.
  # Se habilita con el MISMO atributo (var.ttl_attribute_name) que las tablas
  # padre, así que el productor escribe el mismo epoch en ambas.
  #
  # TODO: validar contra platform-knowledge-base / equipo de Central Log —
  # ¿el payload debe expirar en el MISMO momento que su log padre (asumido
  # aquí, es lo que evita huérfanos) o algún requisito de auditoría exige que
  # el payload sobreviva al log? Si sobrevive, esto NO es un booleano: haría
  # falta un desfase de retención propio para las tablas de payloads.
  payload_ttl_enabled = true

  # ── CATÁLOGO DE TABLAS — LOCKED ───────────────────────────────────────
  # Solo se declaran los atributos que participan en una key (tabla o GSI):
  # DynamoDB es schemaless y rechaza `attribute` blocks que no estén indexados.
  # Los atributos no-clave de cada ítem se documentan como comentario.
  tables_raw = {
    # PK: application_code
    # Atributos no-clave: nombre, estado, descripcion, creation_date
    applications = {
      hash_key         = "application_code"
      range_key        = null
      attributes       = { application_code = "S" }
      ttl_enabled      = false
      stream_view_type = null
    }

    # PK compuesta: service_code (HASH) + application_code (RANGE)
    # Atributos no-clave: estado, tipo, service_name
    services = {
      hash_key  = "service_code"
      range_key = "application_code"
      attributes = {
        service_code     = "S"
        application_code = "S"
      }
      ttl_enabled      = false
      stream_view_type = null
    }

    # PK: id_log — tabla caliente de trazabilidad (4 GSIs, ver local.gsis)
    # Atributos no-clave: client_id (+ el atributo TTL)
    logs = {
      hash_key  = "id_log"
      range_key = null
      # Los atributos clave de los GSIs DEBEN declararse en la tabla base.
      attributes = {
        id_log                        = "S"
        application_code              = "S"
        service_code                  = "S"
        timestamp                     = "N" # epoch
        (local.logs_status_attribute) = "S"
        user_name                     = "S"
      }
      ttl_enabled      = true
      stream_view_type = null
    }

    # PK: id_log (1:1 con `logs`) — payloads separados para no inflar la tabla
    # caliente ni sus GSIs con blobs.
    # Atributos no-clave: data_in, data_out, additional_data, data_type (+ TTL)
    #
    # TTL ESPEJO — ver `local.payload_ttl_enabled`.
    log-payloads = {
      hash_key         = "id_log"
      range_key        = null
      attributes       = { id_log = "S" }
      ttl_enabled      = local.payload_ttl_enabled
      stream_view_type = null
    }

    # PK: id_wait_log — Streams ON: el Lambda `wait-processor` reacciona a los
    # cambios de estado.
    # Atributos no-clave: application_code, service_code, estado (+ atributo TTL)
    wait-logs = {
      hash_key         = "id_wait_log"
      range_key        = null
      attributes       = { id_wait_log = "S" }
      ttl_enabled      = true
      stream_view_type = "NEW_AND_OLD_IMAGES"
    }

    # PK: id_wait_log (1:1 con `wait-logs`)
    # Atributos no-clave: data_in, data_out, additional_data, data_type (+ TTL)
    #
    # TTL ESPEJO — ver `local.payload_ttl_enabled`.
    wait-payloads = {
      hash_key         = "id_wait_log"
      range_key        = null
      attributes       = { id_wait_log = "S" }
      ttl_enabled      = local.payload_ttl_enabled
      stream_view_type = null
    }
  }

  # Normalización de tipos: sin esto, el for_each de main.tf no puede unificar
  # los `attributes` (object types distintos por tabla) en un único map.
  tables = {
    for key, cfg in local.tables_raw : key => {
      hash_key         = tostring(cfg.hash_key)
      range_key        = cfg.range_key == null ? null : tostring(cfg.range_key)
      attributes       = tomap(cfg.attributes)
      ttl_enabled      = tobool(cfg.ttl_enabled)
      stream_view_type = cfg.stream_view_type == null ? null : tostring(cfg.stream_view_type)
    }
  }

  # ── GSIs por tabla — LOCKED (la proyección es FREE) ───────────────────
  # Se mantienen fuera de local.tables para no romper la unificación de tipos
  # del for_each (5 tablas sin índices vs 1 con índices).
  gsis = {
    logs = {
      "application-code-timestamp-index" = { hash_key = "application_code", range_key = "timestamp" }
      "service-code-timestamp-index"     = { hash_key = "service_code", range_key = "timestamp" }
      "status-timestamp-index"           = { hash_key = local.logs_status_attribute, range_key = "timestamp" }
      "user-name-timestamp-index"        = { hash_key = "user_name", range_key = "timestamp" }
    }
  }

  # ── KMS resolution ────────────────────────────────────────────────────────
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_alias.dynamodb[0].target_key_arn

  # ── Capacity resolution (solo aplica con PROVISIONED) ────────────────────
  is_provisioned = var.billing_mode == "PROVISIONED"
  read_capacity  = local.is_provisioned ? var.provisioned_read_capacity : null
  write_capacity = local.is_provisioned ? var.provisioned_write_capacity : null

  # ── GUARD-RAIL — Deletion protection ─────────────────────────────────
  # Piso ON en prod-like (mismo criterio que aurora-postgresql). El hijo puede
  # activarla en dev/qa, nunca desactivarla en preprod/prod/dr.
  # TODO: validar contra platform-knowledge-base.
  deletion_protection_floor   = local.is_prod_like
  deletion_protection_enabled = local.deletion_protection_floor || coalesce(var.deletion_protection_enabled, false)

  # ── GUARD-RAIL — Retención TTL (piso por ambiente) ───────────────────
  # Informativo para el productor de ítems (ver output ttl_retention_days).
  # TODO: validar contra platform-knowledge-base (requisitos regulatorios).
  ttl_retention_floor_days = local.is_prod_like ? 365 : 30
  ttl_retention_days       = max(local.ttl_retention_floor_days, coalesce(var.ttl_retention_days, local.ttl_retention_floor_days))

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
