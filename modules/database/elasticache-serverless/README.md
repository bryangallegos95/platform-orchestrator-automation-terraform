# Módulo `database/elasticache-serverless`

> Cache **ElastiCache Serverless** (Valkey/Redis) hardenizado, desplegado dentro de una Spoke VPC existente.

---

## Descripción

Cache serverless con escalado automático, cifrado completo y autenticación IAM. Soporta Valkey (recomendado — 33% menor costo, Apache 2.0) y Redis OSS.

---

## Features

- **Valkey 8 / Redis 7** — Motor configurable (Valkey recomendado)
- **TLS en tránsito** — Forzado por ElastiCache Serverless (no deshabilitadle)
- **CMK en reposo** — `alias/ElastiCache` (cuenta baseline)
- **IAM Authentication** — Conexiones sin password desde pods IRSA
- **VPC-only** — Sin acceso público
- **FinOps guard-rails** — Techos de ECPU y storage por ambiente

---

## Limitación: Log Delivery NO Soportado

> **AWS (2026-08):** "Log delivery is not supported for serverless caches."

El módulo **pre-provisiona** dos CloudWatch Log Groups (slow-log + engine-log) con retención y CMK correctos, pero **no puede configurar log delivery** en serverless caches. Los log groups quedan listos para cuando AWS habilite esta funcionalidad.

| Log Group | Patrón de Nombre |
|-----------|------------------|
| Slow log | `/aws/elasticache/{cache-name}/slow-log` |
| Engine log | `/aws/elasticache/{cache-name}/engine-log` |

---

## Contrato de Configuración (3 Capas)

### LOCKED

| Control | Valor |
|---------|-------|
| TLS in-transit | Forzado (serverless) |
| CMK at-rest | `alias/ElastiCache` |
| VPC-only | Sin acceso público |
| IAM Auth | Habilitado |
| SG default | Deny-all inbound |

### GUARD-RAIL

| Control | dev / qa | preprod | prod / dr |
|---------|----------|---------|-----------|
| Snapshot retention (piso) | 1 d | 1 d | 7 d |
| ECPU ceiling | Auto | Auto | Auto |
| Storage ceiling | Auto | Auto | Auto |
| Log retention | 30 d | 90 d | 365 d |

### FREE

- `engine` (valkey/redis)
- `major_engine_version`
- `max_ecpu_per_second`, `max_data_storage_gb` (dentro del techo)
- `daily_snapshot_time`
- `allowed_security_group_ids`, `allowed_cidrs`
- `user_group_id`
- `extra_tags`

---

## Descubrimiento

| Recurso | Cómo se resuelve |
|---------|------------------|
| Spoke VPC | tag `ou = {var.service}` |
| Subnets Cache | tags `Tier=cache` + `AZ=a\|b` dentro de la VPC |
| CMK ElastiCache | `alias/ElastiCache` (o `kms_key_arn`) |
| CMK CloudWatch Logs | `alias/CWLogs` (o `cloudwatch_logs_kms_key_arn`) |

---

## Outputs

| Output | Descripción |
|--------|-------------|
| `cache_name` | Nombre del cache serverless |
| `cache_arn` | ARN del cache |
| `endpoint` | Endpoint primario `{address, port}` |
| `reader_endpoint` | Endpoint reader `{address, port}` |
| `security_group_id` | SG del módulo |
| `kms_key_arn` | CMK de cifrado at-rest |
| `vpc_id` | VPC donde está desplegado |
| `log_group_names` | Map: slow_log, engine_log (nombres de log groups) |

---

## Métricas CloudWatch Disponibles

ElastiCache Serverless publica las siguientes métricas nativas (no requieren configuración):

| Métrica | Descripción | Unidad |
|---------|-------------|--------|
| `ElastiCacheProcessingUnits` | ECPUs consumidos por segundo | Count |
| `BytesUsedForCache` | Memoria usada por datos | Bytes |
| `CacheHits` / `CacheMisses` | Hits y misses | Count |
| `CurrConnections` | Conexiones activas | Count |
| `NewConnections` | Nuevas conexiones por segundo | Count |
| `SuccessfulReadRequests` | Lecturas exitosas | Count |
| `SuccessfulWriteRequests` | Escrituras exitosas | Count |
| `ThrottledRequests` | Requests throttled por límite ECPU | Count |

---

## Uso

```hcl
redis_enabled = true
redis_config = {
  engine               = "valkey"
  major_engine_version = "8"
  max_ecpu_per_second  = 5000
  max_data_storage_gb  = 5
  # allowed_security_group_ids = ["sg-XXXXXXXXX"]
}
```
