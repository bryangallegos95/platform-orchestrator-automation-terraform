# AGENTS.md — platform-orchestrator-automation-terraform

## Read First
Clone and read `bin-transversales-devops/platform-knowledge-base` before making changes here.
That repo contains: naming conventions, security baselines, account maps, and architecture patterns.

## What This Repo Is
Central Terraform module library (building blocks) + reusable CI/CD workflows (ci.yml, cd.yml).
All "son repos" consume modules from here via `git::...?ref=v3.1.0`.

**Current version: v3.1.0**

## Architecture
- `modules/product/` — COMPOSITOR (Layer 2): orchestrates all building blocks into a single Terraform state per environment
- `modules/{category}/{module}/` — Individual building blocks (Layer 1): each is self-sufficient (VPC/KMS discovery)
- `.github/workflows/` — Reusable CI/CD workflows consumed by son repos

## Key Files
- `modules/product/` — Compositor (Layer 2): aurora.tf, sqs.tf, redis.tf, irsa.tf, newrelic.tf
- `modules/database/aurora-postgresql/` — Aurora Serverless v2 (port 15432, CMK, IAM Auth)
- `modules/database/elasticache-serverless/` — Valkey Serverless (TLS forced, IAM Auth)
- `modules/messaging/sqs/` — SQS queues with mandatory DLQ (CMK, deny non-TLS, alarms)
- `modules/identity/irsa-role/` — IRSA roles for ROSA pods (StringEquals trust)
- `modules/observability/newrelic-spoke/` — CloudWatch subscription filters → New Relic hub
- `.github/workflows/ci.yml` — Reusable CI (format, lint, plan, cost, PR)
- `.github/workflows/cd.yml` — Reusable CD (apply, rollback, promote, Port lifecycle)

## Module Pattern
Every module has: main.tf, variables.tf, outputs.tf, locals.tf, data.tf, guards.tf, versions.tf
Plus domain-specific: kms.tf, security_groups.tf, policies.tf, parameter_groups.tf, alarms.tf, logs.tf

## Three-Tier Hardening (CRITICAL)
- LOCKED: agent CANNOT override (encryption, TLS, ports, audit logging)
- GUARD-RAIL: agent may raise floor but never lower (backup retention, ACU ceiling)
- FREE: agent/dev configures freely (instance class, queue names, ACU within ceiling)

## Compositor Native Dependencies
The compositor (modules/product) resolves cross-block dependencies:
- IRSA roles get auto-generated policies for Aurora (rds-db:connect), SQS (*), Redis (Connect)
- New Relic spoke receives consolidated all_log_group_names from all blocks
- No circular dependencies — IRSA policies include KMS actions instead of kms_consumer_role_arns

## Build/Test
```bash
cd modules/{category}/{module} && terraform init -backend=false && terraform validate
terraform fmt -check -recursive modules/
```

## Do NOT
- Create KMS keys (discover by alias)
- Use default ports (15432, not 5432; 6380, not 6379)
- Allow public access
- Use aws-managed encryption keys
- Add variables for LOCKED settings
- Modify protected parameter names in Aurora
- Create circular dependencies in the compositor

## Related Repos
- `iac-tfn-infrastructure-template-aws` (v3.3.0) — Template cloned at scaffold
- `platform-archetype-factory-automation-terraform` — Factory: creates repos, scaffolds
- `platform-knowledge-base` — Authoritative platform documentation
