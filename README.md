# Platform Orchestrator — Terraform Automation

![Version](https://img.shields.io/badge/version-v3.1.0-blue)
![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.11-purple)
![Terragrunt](https://img.shields.io/badge/terragrunt-%3E%3D0.69-green)

> Biblioteca centralizada de módulos Terraform (building blocks) y workflows CI/CD reutilizables para todas las cargas de trabajo AWS en la organización multi-cuenta de Banco Internacional.

**Knowledge Base:** [platform-knowledge-base](https://github.com/bin-transversales-devops/platform-knowledge-base)

---

## Descripción

Este repositorio es el **núcleo de la plataforma IDP** (Internal Developer Platform). Proporciona:

1. **Building Blocks** — Módulos Terraform hardenizados que los equipos de producto consumen como self-service
2. **Compositor** (`modules/product`) — Capa de orquestación que compone múltiples building blocks en un solo estado Terraform por ambiente
3. **Workflows reutilizables** — CI/CD (ci.yml, cd.yml) que los repos hijos invocan via `workflow_call`
4. **Contrato de hardening** — Tres capas (LOCKED / GUARD-RAIL / FREE) que garantizan seguridad sin sacrificar agilidad

Los "repos hijos" (scaffoldeados por la [factory](https://github.com/bin-transversales-devops/platform-archetype-factory-automation-terraform)) consumen módulos de aquí vía git source con tag fijado:

```hcl
source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/product?ref=v3.1.0"
```

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Platform Orchestrator (este repo)                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  .github/workflows/                                                      │
│  ├── ci.yml      ← CI reutilizable: format → lint → plan → cost → PR    │
│  ├── cd.yml      ← CD reutilizable: apply → rollback → promotion issue  │
│  ├── release.yml ← Release manual: validate → tag → GH Release          │
│  └── emergency-cluster-ops.yml ← Operaciones ROSA emergencia            │
│                                                                          │
│  modules/                                                                │
│  ├── product/         ← COMPOSITOR (Layer 2) — orquesta building blocks  │
│  ├── database/        (aurora-postgresql, elasticache-serverless)         │
│  ├── identity/        (irsa-role)                                        │
│  ├── messaging/       (sqs)                                              │
│  ├── observability/   (newrelic-spoke)                                   │
│  ├── compute/         (ec2)                                              │
│  ├── integration/     (appflow, kinesis-firehose, s3-private)            │
│  ├── networking/      (centralized-endpoints, palo-alto-vmseries, vpc)   │
│  └── openshift/       (account-bootstrap, cluster-config, rosa-hcp)      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
         ▲                                    ▲
         │  workflow_call                      │  git::...?ref=v3.1.0
         │                                    │
┌────────┴───────────┐             ┌──────────┴──────────────────────┐
│  Son Repo A        │             │  Son Repo B                      │
│  (iac-tfn-pagos)   │             │  (iac-tfn-notificaciones)        │
└────────────────────┘             └─────────────────────────────────┘
```

### Modelo de Capas (Building Blocks)

```
┌─────────────────────────────────────────────┐
│  Layer 2: Compositor (modules/product)       │
│  Orquesta building blocks, resuelve deps     │
│  nativas (IRSA → Aurora/SQS/Redis policies)  │
├─────────────────────────────────────────────┤
│  Layer 1: Building Blocks individuales       │
│  aurora-postgresql | elasticache-serverless  │
│  sqs | irsa-role | newrelic-spoke            │
│  Cada uno es auto-suficiente (VPC/KMS disc.) │
└─────────────────────────────────────────────┘
```

---

## Módulos Disponibles (Building Blocks)

### Consumibles via `modules/product` (compositor)

| Módulo | Flag | Descripción |
|--------|------|-------------|
| `database/aurora-postgresql` | `aurora_enabled` | Aurora PostgreSQL Serverless v2 (puerto 15432, CMK, IAM Auth, pgaudit) |
| `database/elasticache-serverless` | `redis_enabled` | ElastiCache Serverless Valkey/Redis (TLS forzado, CMK, IAM Auth) |
| `messaging/sqs` | `sqs_enabled` | SQS con DLQ obligatorio (CMK, deny non-TLS, alarmas CloudWatch) |
| `identity/irsa-role` | `irsa_enabled` | Roles IRSA para pods ROSA HCP (1:1 ServiceAccount) |
| `observability/newrelic-spoke` | `newrelic_enabled` | Subscription filters al hub New Relic centralizado |

### Módulos de Infraestructura (uso directo)

| Categoría | Módulo | Descripción |
|-----------|--------|-------------|
| **compute** | `ec2` | Instancia EC2 (IMDSv2, EBS cifrado, SSM) |
| **integration** | `appflow` | Amazon AppFlow connectors y flows |
| **integration** | `kinesis-firehose` | Kinesis Data Firehose delivery streams |
| **integration** | `s3-private` | Buckets S3 privados con cifrado y lifecycle |
| **networking** | `centralized-endpoints` | VPC Interface Endpoints compartidos |
| **networking** | `palo-alto-vmseries` | Firewalls Palo Alto VM-Series |
| **networking** | `vpc` | Spoke VPC para topología Hub-and-Spoke (TGW) |
| **openshift** | `account-bootstrap` | Baseline AWS account para ROSA |
| **openshift** | `cluster-config` | Configuración day-2 ROSA cluster |
| **openshift** | `rosa-hcp` | Provisioning ROSA HCP cluster |

---

## Historial de Versiones

| Versión | Fecha | Cambios Principales |
|---------|-------|---------------------|
| `v3.1.0` | 2026-07 | New Relic spoke module, compositor `all_log_group_names` output |
| `v3.0.1` | 2026-07 | Fix: aurora `resource_suffix` naming convention |
| `v3.0.0` | 2026-06 | Compositor `modules/product` (1 estado por env), IRSA native deps |
| `v2.1.0` | 2026-04 | ElastiCache Serverless, SQS alarms, guards refactor |
| `v2.0.0` | 2026-02 | Aurora Serverless v2, 3-tier hardening contract |

---

## Contrato de Hardening (3 Capas)

Cada módulo implementa un contrato de seguridad de tres capas:

| Capa | Regla | Ejemplos |
|------|-------|----------|
| **LOCKED** | No se puede override | Cifrado (CMK), TLS forzado, puertos no-default (15432, 6380), audit logging, IAM Auth |
| **GUARD-RAIL** | Piso que se puede subir pero nunca bajar | Retención backup (min 7d), techo ACU (por env), monitoring en prod, IRSA 1:1 SA |
| **FREE** | Configurable libremente | instance_class, nombres de colas, ACU dentro del techo, database_name, extra_tags |

---

## Workflows Reutilizables

### `ci.yml` — Terraform CI

| Job | Qué hace |
|-----|----------|
| Resolve | Deriva región, bucket S3, state key del ambiente |
| Format | `terragrunt hclfmt --check --diff` |
| Lint | `tflint` con plugin AWS |
| Plan | `terragrunt validate` + `plan` con `-detailed-exitcode` |
| Cost | `infracost breakdown` (solo si hay cambios) |
| Security | Prowler IaC scan |
| Create PR | Auto-crea PR con plan output + `DEPLOYMENT_CONTEXT` |

### `cd.yml` — Terraform CD

| Job | Qué hace |
|-----|----------|
| Resolve | Deriva región, bucket, state key |
| Apply | Descarga plan binario de CI → `terragrunt apply tfplan` |
| Promotion Issue | Crea GitHub Issue con `/approve` y `/reject` |
| Port.io Update | Actualiza lifecycle + aws_accounts en la entidad |

**Comportamientos clave:**
- Aplica el plan **exacto** de CI (no re-plan)
- Auto-rollback en dev/qa si falla; alerta en preprod/prod/dr
- Ventana de cambio: prod bloqueado en horario Ecuador (Lun-Vie 08:30-17:30 UTC-5)
- Cadena de promoción: dev → qa → preprod → prod → dr

### `release.yml` — Module Release

Trigger manual para crear release versionado: `terraform validate` → tag → GitHub Release.

---

## Convención de Nombres

Patrón: `{TIPO}-aw-{REGION}-{WORKLOAD}-{FUNCIONALIDAD}-{AMBIENTE}`

| Componente | Valores |
|------------|---------|
| TIPO | `rds`, `sqs`, `ec2`, `vpc`, `sgp`, `rol`, etc. |
| REGION | `ue1` (us-east-1), `ue2` (us-east-2) |
| WORKLOAD | Nombre corto del producto (ej: `pagos-core`) |
| FUNCIONALIDAD | Propósito del repo (ej: `backingservices`) |
| AMBIENTE | `dev`, `qa`, `preprod`, `prod`, `dr` |

Ejemplo: `rds-aw-ue1-pagos-core-backingservices-prod`

---

## Mapeo Ambiente → Región → Bucket

| Ambiente | Región | State Bucket |
|----------|--------|--------------|
| `dev` | `us-east-1` | `s3-aw-ue1-terraform-state-dev` |
| `qa` | `us-east-1` | `s3-aw-ue1-terraform-state-qa` |
| `preprod` | `us-east-1` | `s3-aw-ue1-terraform-state-preprod` |
| `prod` | `us-east-1` | `s3-aw-ue1-terraform-state-prod` |
| `dr` | `us-east-2` | `s3-aw-ue2-terraform-state-dr` |

---

## Build / Test / Validate

```bash
# Format check
terraform fmt -check -recursive modules/

# Validación de módulo individual
cd modules/{category}/{module}
terraform init -backend=false
terraform validate

# Validación de naming (requiere plan JSON)
./scripts/naming_pattern_validator.sh tfplan.json [--strict]
```

---

## Cómo Agregar un Nuevo Módulo

1. **Crear el módulo** en `modules/{category}/{module}/`
   - Archivos requeridos: `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `versions.tf`
   - Opcional: `data.tf`, `guards.tf`, `kms.tf`, `security_groups.tf`

2. **Implementar el contrato de 3 capas:**
   - Definir qué es LOCKED (hardcoded en locals)
   - Definir GUARD-RAILs (validaciones + coalesce con pisos por ambiente)
   - Documentar qué es FREE (variables expuestas)

3. **Integrar en el compositor** (`modules/product/`):
   - Crear `{module}.tf` con el `module` block (count = `var.{module}_enabled`)
   - Agregar `{module}_enabled` + `{module}_config` a `variables.tf`
   - Exponer outputs en `outputs.tf`
   - Si genera log groups → agregar a `all_log_group_names` en `newrelic.tf`

4. **Registrar en el template** ([iac-tfn-infrastructure-template-aws](https://github.com/bin-transversales-devops/iac-tfn-infrastructure-template-aws)):
   - Agregar snippet en `snippets/{module}.hcl`
   - Agregar entrada en `metadata/component-registry.json`

5. **Release:**
   - PR → merge a master → Actions → Release → nueva versión

---

## Estructura del Repositorio

```
.
├── .github/workflows/
│   ├── ci.yml                    # CI reutilizable (format, lint, plan, cost, PR)
│   ├── cd.yml                    # CD reutilizable (apply, rollback, promote)
│   ├── release.yml               # Release tagging
│   └── emergency-cluster-ops.yml # Operaciones emergencia ROSA
├── modules/
│   ├── product/                  # COMPOSITOR — Layer 2 (orquesta building blocks)
│   ├── database/
│   │   ├── aurora-postgresql/    # Aurora PostgreSQL (15432, CMK, pgaudit)
│   │   └── elasticache-serverless/ # Valkey Serverless (TLS, IAM Auth)
│   ├── identity/
│   │   └── irsa-role/            # IRSA roles (1:1 SA, native deps)
│   ├── messaging/
│   │   └── sqs/                  # SQS con DLQ obligatorio + alarmas
│   ├── observability/
│   │   └── newrelic-spoke/       # Subscription filters → hub NR
│   ├── compute/
│   │   └── ec2/                  # EC2 (IMDSv2, cifrado, SSM)
│   ├── integration/
│   │   ├── appflow/              # Amazon AppFlow
│   │   ├── kinesis-firehose/     # Kinesis Data Firehose
│   │   └── s3-private/           # S3 privado con cifrado
│   ├── networking/
│   │   ├── centralized-endpoints/ # VPC Endpoints compartidos
│   │   ├── palo-alto-vmseries/   # Firewalls Palo Alto
│   │   └── vpc/                  # Spoke VPC (Hub-and-Spoke, TGW)
│   └── openshift/
│       ├── account-bootstrap/    # Baseline AWS para ROSA
│       ├── cluster-config/       # Configuración day-2 ROSA
│       └── rosa-hcp/             # ROSA HCP cluster
├── scripts/
│   └── naming_pattern_validator.sh # Validación naming empresarial
└── docs/
    └── dr-backing-services.md    # Procedimientos DR
```

---

## Runner Requirements

| Requisito | Detalle |
|-----------|---------|
| Imagen | `runner-gh-aws-terraform:2.0.0` |
| Pre-instalado | Terraform 1.11.4, Terragrunt 0.69.10, TFLint 0.55.0, Infracost 0.10.40, gh CLI 2.65.0 |
| Labels | `self-hosted, linux, terraform, aws, {env}` |
| IAM | IRSA via `runner-pivot-role-{env}` → assumes `terraform-apply-role` en cuenta destino |

---

## Repositorios Relacionados

| Repositorio | Relación |
|-------------|----------|
| [iac-tfn-infrastructure-template-aws](https://github.com/bin-transversales-devops/iac-tfn-infrastructure-template-aws) | Template que se clona al scaffold (v3.3.0) |
| [platform-archetype-factory-automation-terraform](https://github.com/bin-transversales-devops/platform-archetype-factory-automation-terraform) | Factory: crea repos, scaffold, configura Port |
| [platform-knowledge-base](https://github.com/bin-transversales-devops/platform-knowledge-base) | Documentación autoritativa de la plataforma |
