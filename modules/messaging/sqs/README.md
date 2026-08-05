# Módulo `messaging/sqs`

> Colas **SQS** hardenizadas con DLQ obligatorio, cifrado CMK y alarmas CloudWatch incluidas.

---

## Descripción

Una llamada al módulo = N colas (map-driven). Cada cola **siempre** tiene una Dead Letter Queue asociada. El módulo no requiere VPC (SQS es un servicio gestionado regional).

---

## Features

- **DLQ obligatorio** — Toda cola principal tiene una DLQ (reliability baseline)
- **CMK** — Cifrado server-side con `alias/SQS_SNS` (cuenta baseline)
- **Deny non-TLS** — Queue policy rechaza requests sin TLS
- **Deny cross-account** — Queue policy rechaza requests de otras cuentas AWS
- **Long-polling** — `receive_wait_time_seconds = 20` por defecto
- **CloudWatch Alarms** — DLQ depth + message age (incluidas automáticamente)
- **FIFO soportado** — Standard y FIFO con content-based deduplication

---

## Qué Crea (por cola)

| Recurso | Descripción |
|---------|-------------|
| `aws_sqs_queue.main` | Cola principal (Standard o FIFO) |
| `aws_sqs_queue.dlq` | Dead Letter Queue |
| `aws_sqs_queue_policy.main` | Policy: deny non-TLS + deny non-owner |
| `aws_sqs_queue_policy.dlq` | Policy: deny non-TLS + deny non-owner |
| `aws_sqs_queue_redrive_allow_policy` | Permite al main queue enviar a DLQ |
| `aws_cloudwatch_metric_alarm.dlq_depth` | Alarma: mensajes en DLQ |
| `aws_cloudwatch_metric_alarm.queue_age` | Alarma: edad del mensaje más viejo |

---

## CloudWatch Alarms

### DLQ Depth Alarm

- **Métrica:** `ApproximateNumberOfMessagesVisible` en la DLQ
- **Threshold default:** `0` (cualquier mensaje en DLQ es anormal)
- **Período:** 5 minutos
- **Significado:** Hay mensajes que fallaron el procesamiento N veces

### Message Age Alarm

- **Métrica:** `ApproximateAgeOfOldestMessage` en la cola principal
- **Threshold default:** `300` segundos (5 minutos)
- **Período:** 5 minutos
- **Significado:** Consumers no están procesando mensajes (stuck o lento)

### Override de Thresholds

```hcl
sqs_config = {
  alarm_dlq_threshold         = 5     # permite hasta 5 msgs en DLQ antes de alertar
  alarm_age_threshold_seconds = 600   # 10 minutos
  alarm_actions = ["arn:aws:sns:us-east-1:123456789012:alertas-infra"]
}
```

---

## Contrato de Configuración (3 Capas)

### LOCKED

| Control | Valor |
|---------|-------|
| Cifrado | CMK `alias/SQS_SNS` (SSE-KMS, siempre) |
| Queue policy | Deny non-TLS (`aws:SecureTransport = false`) |
| Queue policy | Deny non-owner account |
| DLQ | Siempre creada (no optional) |
| Long-polling | `receive_wait_time_seconds` default 20s |

### GUARD-RAIL

| Control | Rango |
|---------|-------|
| `message_retention_days` | 1-14 días |
| `dlq_max_receive_count` | 1-1000 |
| `dlq_message_retention_days` | 1-14 días |
| `visibility_timeout_seconds` | 0-43200 (12h) |
| `max_message_size_bytes` | 1024-262144 (256KB) |

### FREE

- Nombres de colas (keys del map)
- `fifo` (Standard vs FIFO)
- `delay_seconds` (0-900)
- `content_based_deduplication`
- `alarm_dlq_threshold`, `alarm_age_threshold_seconds`
- `alarm_actions` (SNS topics)
- `kms_data_key_reuse_period_seconds` (60-86400)
- `extra_tags`

---

## Naming Convention

| Recurso | Patrón |
|---------|--------|
| Cola principal | `sqs-aw-{region}-{workload}-{funcionalidad}-{queue_key}-{ambiente}` |
| DLQ | `sqs-aw-{region}-{workload}-{funcionalidad}-{queue_key}-dlq-{ambiente}` |
| FIFO suffix | `.fifo` (agregado automáticamente si `fifo = true`) |

---

## Outputs

| Output | Descripción |
|--------|-------------|
| `queue_arns` | Map queue_key → ARN cola principal |
| `queue_urls` | Map queue_key → URL cola principal |
| `queue_names` | Map queue_key → nombre cola principal |
| `dlq_arns` | Map queue_key → ARN DLQ |
| `dlq_urls` | Map queue_key → URL DLQ |
| `kms_key_arn` | ARN de la CMK SQS |
| `dlq_alarm_arns` | Map queue_key → DLQ depth alarm ARN |
| `age_alarm_arns` | Map queue_key → message age alarm ARN |

---

## Uso

```hcl
sqs_enabled = true
sqs_queues = {
  notificaciones = {
    fifo                       = false
    visibility_timeout_seconds = 30
    message_retention_days     = 4
    receive_wait_time_seconds  = 20
    dlq_max_receive_count      = 3
  }
  pagos = {
    fifo                        = true
    content_based_deduplication = true
    message_retention_days      = 14
    dlq_max_receive_count       = 5
  }
}
sqs_config = {
  alarm_actions = ["arn:aws:sns:us-east-1:123456789012:alertas"]
}
```
