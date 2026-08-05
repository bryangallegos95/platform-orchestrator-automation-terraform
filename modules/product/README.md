# Compositor — `modules/product`

> **Layer 2** del modelo Building Blocks. Orquesta módulos individuales (Layer 1) en un solo estado Terraform por ambiente.

---

## Descripción

El compositor **no crea recursos AWS directamente**. Su rol es:

1. Instanciar building blocks seleccionados (via flags `*_enabled`)
2. Resolver **dependencias nativas** entre blocks (ej: IRSA policies que referencian outputs de Aurora/SQS/Redis)
3. Consolidar outputs para consumidores downstream (Helm, ArgoCD, monitoring)
4. Propagar variables de identidad comunes a todos los child modules

```
┌─────────────────────────────────────────────────────────────┐
│  modules/product (Compositor)                                │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Aurora   │  │   SQS    │  │  Redis   │  │  IRSA    │   │
│  │ (Layer1)  │  │ (Layer1) │  │ (Layer1) │  │ (Layer1) │   │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘   │
│        │              │              │              │        │
│        └──────────────┴──────────────┴──────────────┘        │
│                          │                                    │
│                  Native dependency                            │
│                  resolution (IAM policies)                    │
│                          │                                    │
│  ┌──────────────────────┴───────────────────────────────┐   │
│  │  New Relic Spoke (subscription filters)               │   │
│  │  Consume: all_log_group_names                         │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Inputs Obligatorios (Identity Variables)

Estas variables se pasan a **todos** los building blocks:

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `aws_region` | Región AWS (`us-east-1` o `us-east-2`) | `us-east-1` |
| `service` | Nombre OU (lowercase) — usado para VPC discovery | `contenerizacion` |
| `workload` | Nombre corto del workload (3-30 chars) | `pagos-core` |
| `funcionalidad` | Propósito del repo dentro del workload | `backingservices` |
| `ambiente` | Ambiente: dev, qa, preprod, prod, dr | `prod` |
| `aws_account_id` | Account ID AWS (12 dígitos) | `761018868392` |
| `aplicacion` | Tag corporativo obligatorio | `Pagos` |
| `propietario_recurso` | Tag corporativo obligatorio | `Equipo Pagos` |
| `producto` | Tag corporativo obligatorio | `Banca Digital` |
| `centro_costo` | Tag corporativo obligatorio | `CC-1234` |

---

## Building Blocks y sus Flags

| Building Block | Flag | Config Variable | Descripción |
|----------------|------|-----------------|-------------|
| Aurora PostgreSQL | `aurora_enabled` | `aurora_config` | Cluster Serverless v2, CMK, IAM Auth |
| SQS | `sqs_enabled` | `sqs_queues`, `sqs_config` | Colas con DLQ obligatorio |
| ElastiCache Serverless | `redis_enabled` | `redis_config` | Valkey/Redis con TLS + IAM |
| IRSA | `irsa_enabled` | `irsa_config`, `irsa_roles` | Roles IAM para pods ROSA |
| New Relic Spoke | `newrelic_enabled` | `newrelic_hub_destination_arn` | Log forwarding al hub |

---

## Dependencias Nativas (resolución automática)

El compositor genera automáticamente policies IAM para roles IRSA que necesitan acceso a otros blocks:

| Flag en `irsa_roles[].policies` | Qué genera | Requiere |
|---------------------------------|-----------|----------|
| `aurora_connect = true` | `rds-db:connect` + `kms:Decrypt` | `aurora_enabled = true` |
| `sqs_full = true` | `sqs:*` (Send/Receive/Delete) + `kms:Decrypt/GenerateDataKey` | `sqs_enabled = true` |
| `redis_connect = true` | `elasticache:Connect` + `kms:Decrypt` | `redis_enabled = true` |

Si el flag está `true` pero el block dependiente está disabled, la policy **no se genera** (safe no-op).

---

## Outputs Expuestos

### Aurora PostgreSQL

| Output | Descripción |
|--------|-------------|
| `aurora_cluster_id` | Identificador del cluster |
| `aurora_writer_endpoint` | Endpoint escritura (read/write) |
| `aurora_reader_endpoint` | Endpoint lectura (load-balanced) |
| `aurora_port` | Puerto (siempre 15432) |
| `aurora_iam_auth_resource_arn_prefix` | Prefijo ARN para `rds-db:connect` |
| `aurora_kms_key_arn` | ARN de la CMK de cifrado |
| `aurora_security_group_id` | Security Group del cluster |

### SQS

| Output | Descripción |
|--------|-------------|
| `sqs_queue_arns` | Map queue_key → ARN |
| `sqs_queue_urls` | Map queue_key → URL |
| `sqs_queue_names` | Map queue_key → nombre |
| `sqs_dlq_arns` | Map queue_key → DLQ ARN |
| `sqs_kms_key_arn` | ARN de la CMK SQS |
| `sqs_dlq_alarm_arns` | Map queue_key → DLQ depth alarm ARN |
| `sqs_age_alarm_arns` | Map queue_key → message age alarm ARN |

### ElastiCache Serverless

| Output | Descripción |
|--------|-------------|
| `redis_cache_name` | Nombre del cache |
| `redis_endpoint` | Endpoint primario (address + port) |
| `redis_reader_endpoint` | Endpoint reader |
| `redis_security_group_id` | Security Group del cache |
| `redis_kms_key_arn` | ARN de la CMK ElastiCache |

### IRSA

| Output | Descripción |
|--------|-------------|
| `irsa_role_arns` | Map role_key → IAM role ARN |
| `irsa_role_names` | Map role_key → IAM role name |
| `irsa_sa_annotations` | Map role_key → annotation value para SA |
| `irsa_oidc_provider_arn` | ARN del OIDC provider |

### Observability

| Output | Descripción |
|--------|-------------|
| `all_log_group_names` | Lista consolidada de todos los log groups |
| `newrelic_subscription_filter_arns` | Map log_group → filter ARN |
| `newrelic_iam_role_arn` | Role que CW Logs asume para el spoke |

---

## Ejemplo de Uso (terragrunt.hcl)

```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/product?ref=v3.1.0"
}

inputs = {
  # ── Context (inyectado por workflow) ──
  ambiente       = "dev"
  workload       = "pagos-core"
  funcionalidad  = "backingservices"
  service        = "contenerizacion"
  aws_region     = "us-east-1"
  aws_account_id = get_env("TF_VAR_aws_account_id", "")

  # ── Tags corporativos ──
  aplicacion          = "Pagos Core"
  propietario_recurso = "Equipo Pagos"
  producto            = "Banca Digital"
  centro_costo        = "CC-1234"

  # ── Aurora PostgreSQL ──
  aurora_enabled = true
  aurora_config = {
    engine_version = "17.7"
    serverless     = true
    min_acu        = 0
    max_acu        = 4
    database_name  = "app_db"
  }

  # ── SQS ──
  sqs_enabled = true
  sqs_queues = {
    notificaciones = {
      fifo                       = false
      visibility_timeout_seconds = 30
      message_retention_days     = 4
    }
  }

  # ── IRSA ──
  irsa_enabled = true
  irsa_config = {
    oidc_issuer_url = "rh-oidc.s3.us-east-1.amazonaws.com/xxxxx"
  }
  irsa_roles = {
    api-consumer = {
      namespace       = "pagos"
      service_account = "pagos-sa"
      policies = {
        aurora_connect = true
        sqs_full       = true
        redis_connect  = false
      }
    }
  }

  # ── New Relic ──
  newrelic_enabled             = true
  newrelic_hub_destination_arn = get_env("NR_HUB_DESTINATION_ARN", "")
}
```

---

## Secretos

| Variable | Fuente | Cuándo se requiere |
|----------|--------|--------------------|
| `master_password` | BeyondTrust → `TF_VAR_master_password` | `aurora_enabled = true` |

El workflow de CI inyecta secretos desde BeyondTrust Secrets Safe usando el campo `secret_titles` del orchestrator.
