# Platform Orchestrator — Steering Context

## What This Repo Is

Central Terraform module library + reusable CI/CD workflows for the IDP (Internal Developer Platform) of Banco Internacional.
All "son repos" (product/service repos) consume modules from here via `git::...?ref=v2.1.0`.

**Current version:** v2.1.0

## Architecture Reference

Before making changes, consult `bin-transversales-devops/platform-knowledge-base`:
- `constraints/naming.md` — naming convention `{TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}`
- `constraints/tagging.md` — 4 mandatory tags (aplicacion, propietario_recurso, producto, centro_costo)
- `constraints/security-baseline.md` — encryption, TLS, non-default ports
- `platform/cicd-terraform-flow.md` — CI/CD pipeline flow (CI → CD → Promotion)
- `components/` — per-component architecture docs

## Repository Structure

```
.github/workflows/
  ci.yml              — Reusable CI (format, lint, plan, cost, security, create-pr)
  cd.yml              — Reusable CD (apply, rollback, promotion-issue)
  emergency-cluster-ops.yml

modules/
  compute/ec2/
  database/aurora-postgresql/     — Aurora Serverless v2 (port 15432, CMK, IAM Auth)
  database/elasticache-serverless/ — Valkey Serverless (TLS, IAM Auth)
  identity/irsa-role/             — IRSA roles for ROSA pods
  integration/appflow/
  integration/kinesis-firehose/
  integration/s3-private/
  messaging/sqs/                  — SQS with mandatory DLQ
  networking/centralized-endpoints/
  networking/palo-alto-vmseries/
  networking/vpc/
  openshift/account-bootstrap/
  openshift/cluster-config/
  openshift/rosa-hcp/

scripts/
  naming_pattern_validator.sh     — Enterprise naming validation (used by CI)

docs/
  dr-backing-services.md
```

## Module Pattern (EVERY module follows this)

Files: `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `data.tf`, `guards.tf`, `versions.tf`
Plus domain-specific: `kms.tf`, `security_groups.tf`, `policies.tf`, `parameter_groups.tf`

## Three-Tier Hardening Contract (CRITICAL)

| Tier | Rule | Examples |
|------|------|----------|
| **LOCKED** | Agent CANNOT override | Encryption at rest/transit, TLS enforcement, non-default ports (15432, 6380), audit logging (pgaudit, force_ssl), max_session 3600s |
| **GUARD-RAIL** | Agent may raise floor but NEVER lower | backup_retention (min 7d), ACU ceiling (256), monitoring_interval in prod |
| **FREE** | Agent/dev configures freely | instance_class, queue names, ACU within ceiling, database_name, extra_tags |

## Naming Convention

Pattern: `{TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}`

- TIPO: `s3`, `kdf`, `appflow`, `role`, `usr`, `pol`, `lam`, `vpc`, `sg`, `aurora`, `sqs`...
- UBICACION: `aw` (AWS), `az` (Azure), `gc` (GCP)
- REGION: `ue1` (us-east-1), `ue2` (us-east-2), `glb` (global)
- FUNCION: 1-6 segments, lowercase alphanumeric + hyphens
- AMBIENTE: `dev`, `qa`, `preprod`, `prod`, `dr`

Example: `aurora-aw-ue1-payments-core-prod`

## CI/CD Workflow Contract

### ci.yml (called by son repos)
- Required inputs: `environment`, `working_directory`, `account_id`, `ou_name`
- Optional: `secret_titles` (BeyondTrust JSON), `extra_vars`, `runner_label`, `security_scan`, `checkmarx_scan`
- Jobs: Resolve → Format → Lint → Plan → Cost → Security (Prowler IaC) → Create PR
- Environments: dev, qa, preprod, prod, dr
- Region mapping: dev/qa/preprod/prod → us-east-1, dr → us-east-2
- State bucket: `s3-aw-ue1-terraform-state-{env}` (dr: `s3-aw-ue2-terraform-state-dr`)

### cd.yml (called by son repos after merge)
- Required inputs: `environment`, `working_directory`, `account_id`, `ou_name`, `plan_artifact_name`, `plan_exitcode`
- Jobs: Resolve → Apply → Promotion Issue
- Rollback: auto-destroy in dev/qa, alert-only in preprod/prod/dr
- Change window: prod blocked during Ecuador business hours (08:30-17:30 UTC-5)
- Promotion: creates GitHub Issue with `/approve` and `/reject` commands

### BeyondTrust Secrets Safe Integration
- `secret_titles` input: JSON array `[{"title": "...", "tf_var": "..."}]`
- Per-environment credentials: `BYT_CLIENT_ID_{ENV}`, `BYT_CLIENT_SECRET_{ENV}`
- Vault scoped by Application User (no folder path needed)
- Flow: OAuth token → SignAppin (session) → List secrets → Fetch by ID → Export as TF_VAR_*

## Mandatory Variables (ALL modules)

Every module requires these identity/tag variables:
- `aws_region` (us-east-1 or us-east-2)
- `service` (lowercase, used for VPC discovery)
- `workload` (lowercase, the specific resource purpose)
- `ambiente` (dev/qa/preprod/prod/dr)
- `aws_account_id` (12-digit)
- `aplicacion` (mandatory tag)
- `propietario_recurso` (mandatory tag)
- `producto` (mandatory tag)
- `centro_costo` (mandatory tag)

## DO NOT (Hard Rules)

- Create KMS keys — discover existing ones by alias (`alias/RDS`, `alias/CWLogs`)
- Use default ports (15432, NOT 5432; 6380, NOT 6379)
- Allow public access to any resource
- Use AWS-managed encryption keys
- Add variables for LOCKED settings
- Modify protected parameter names in Aurora (rds.force_ssl, pgaudit.log, etc.)
- Use `var.service` alone for resource naming — must combine with workload
- Use special characters (em-dash, arrows, unicode) in AWS tags or descriptions
- Override security-baseline parameters (force_ssl, log_connections, etc.)

## Build / Test / Validate

```bash
# Format check
terraform fmt -check -recursive modules/

# Module validation (per module)
cd modules/{category}/{module}
terraform init -backend=false
terraform validate

# Naming validation (requires plan JSON)
./scripts/naming_pattern_validator.sh tfplan.json [--strict]
```

## Cross-Repo Dependencies

| This Repo Provides | Consumed By |
|---------------------|-------------|
| `modules/database/aurora-postgresql/` | All son repos needing Aurora |
| `modules/messaging/sqs/` | Son repos needing queues |
| `modules/identity/irsa-role/` | Son repos needing pod-level AWS access |
| `.github/workflows/ci.yml` | All son repos (workflow_call) |
| `.github/workflows/cd.yml` | All son repos (workflow_call) |
| `scripts/naming_pattern_validator.sh` | CI lint step (checked out at runtime) |
| `.tflint.hcl` | Son repos without their own config |

## Known Issues (Mitigation Plan — Ola 0)

- #6: `var.service` used alone in some resource names (should be `{service}-{workload}`)
- Modules need IRSA 1:1 relationship validation
- Some modules missing `guards.tf` enforcement
