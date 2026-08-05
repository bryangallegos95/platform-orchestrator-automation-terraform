# Módulo `observability/newrelic-spoke`

> Spoke de observabilidad que reenvía logs de CloudWatch al hub centralizado de New Relic via subscription filters.

---

## Arquitectura Hub & Spoke

```
┌─────────────────────────────────────────────────────────────────────┐
│  Cuenta del Workload (Spoke)                                         │
│                                                                      │
│  ┌──────────────────┐     ┌─────────────────────────────────────┐   │
│  │ Aurora Log Group  │────▶│ Subscription Filter (nr-{env}-...)  │   │
│  └──────────────────┘     └──────────────────┬──────────────────┘   │
│                                               │                      │
│  ┌──────────────────┐     ┌──────────────────┼──────────────────┐   │
│  │ (Otros LGs...)   │────▶│ Subscription Filter                 │   │
│  └──────────────────┘     └──────────────────┼──────────────────┘   │
│                                               │                      │
│                           ┌──────────────────┴──────────────────┐   │
│                           │ IAM Role: CW Logs → Destination      │   │
│                           └──────────────────┬──────────────────┘   │
└──────────────────────────────────────────────┼──────────────────────┘
                                               │ Cross-account
                                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Cuenta Hub (CloudOps)                                                │
│                                                                       │
│  ┌────────────────────────┐    ┌────────────────┐    ┌────────────┐ │
│  │ CW Logs Destination    │───▶│ Kinesis Firehose│───▶│  New Relic │ │
│  │ (arn:aws:logs:...)     │    │ (transform)     │    │  (OTLP)   │ │
│  └────────────────────────┘    └────────────────┘    └────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Qué Crea Este Módulo

| Recurso | Nombre | Propósito |
|---------|--------|-----------|
| `aws_iam_role` | `rol-aw-{region}-{workload}-{func}-nr-spoke-{env}` | Role que CloudWatch Logs asume para escribir al destination |
| `aws_iam_role_policy` | `nr-spoke-put-logs` | Permisos: `logs:PutLogEvents`, `firehose:PutRecord*`, `kinesis:PutRecord*` |
| `aws_cloudwatch_log_subscription_filter` | `nr-{env}-{log-group-sanitized}` | Un filtro por log group → destination hub |

---

## Inputs

| Variable | Tipo | Requerido | Descripción |
|----------|------|-----------|-------------|
| `aws_region` | string | Si | Región AWS |
| `service` | string | Si | OU name (para naming) |
| `workload` | string | Si | Nombre del workload |
| `funcionalidad` | string | Si | Propósito del repo |
| `ambiente` | string | Si | dev/qa/preprod/prod/dr |
| `aws_account_id` | string | Si | Account ID (condición trust del role) |
| `log_group_names` | list(string) | Si | Log groups a suscribir |
| `hub_destination_arn` | string | Si | ARN del destination cross-account |
| `filter_pattern` | string | No | Filtro CW Logs (`""` = todos los eventos) |

---

## Outputs

| Output | Descripción |
|--------|-------------|
| `subscription_filter_arns` | Map log_group_key → filter ARN |
| `iam_role_arn` | ARN del role IAM del spoke |

---

## Prerequisitos

1. **Hub desplegado por CloudOps** — El Kinesis Firehose + CW Logs Destination deben existir en la cuenta hub
2. **Variable de repo `NR_HUB_DESTINATION_ARN`** — Seteada al scaffold (vacía hasta que CloudOps confirme el hub)
3. **Log groups existentes** — El módulo NO crea log groups; solo se suscribe a los que otros blocks producen

---

## Cómo se Activa

Desde el `terragrunt.hcl` del repo hijo:

```hcl
newrelic_enabled             = true
newrelic_hub_destination_arn = get_env("NR_HUB_DESTINATION_ARN", "")
```

El compositor (`modules/product`) alimenta automáticamente la lista de log groups:

```hcl
# En modules/product/newrelic.tf:
log_group_names = local.all_log_group_names
# Que incluye: Aurora postgresql log group
# (ElastiCache Serverless y SQS no producen log groups)
```

---

## Limitaciones Conocidas

- **ElastiCache Serverless** no produce CloudWatch Log Groups (log delivery solo disponible para replication groups)
- **SQS** no produce CloudWatch Log Groups
- Si `log_group_names` está vacío, el módulo no crea ningún subscription filter (safe no-op)
- El `filter_pattern` vacío ("") reenvía **todos** los eventos de log (recomendado para observabilidad completa)
