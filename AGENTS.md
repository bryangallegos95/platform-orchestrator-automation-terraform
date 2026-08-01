# AGENTS.md — platform-orchestrator-automation-terraform

## Read First
Clone and read `bin-transversales-devops/platform-knowledge-base` before making changes here.
That repo contains: naming conventions, security baselines, account maps, and architecture patterns.

## What This Repo Is
Central Terraform module library (building blocks) + reusable CI/CD workflows (ci.yml, cd.yml).
All "son repos" consume modules from here via `git::...?ref=v2.1.0`.

## Key Files
- `modules/database/aurora-postgresql/` — Aurora Serverless v2 (port 15432, CMK, IAM Auth)
- `modules/messaging/sqs/` — SQS queues with mandatory DLQ (CMK, deny non-TLS)
- `modules/database/elasticache-serverless/` — Valkey Serverless (TLS forced, IAM Auth)
- `modules/identity/irsa-role/` — IRSA roles for ROSA pods (StringEquals trust)
- `.github/workflows/ci.yml` — Reusable CI (format, lint, plan, cost, PR)
- `.github/workflows/cd.yml` — Reusable CD (apply, rollback, promote)

## Module Pattern
Every module has: main.tf, variables.tf, outputs.tf, locals.tf, data.tf, guards.tf, versions.tf
Plus domain-specific: kms.tf, security_groups.tf, policies.tf, parameter_groups.tf

## Three-Tier Hardening (CRITICAL)
- LOCKED: agent CANNOT override (encryption, TLS, ports, audit logging)
- GUARD-RAIL: agent may raise floor but never lower (backup retention, ACU ceiling)
- FREE: agent/dev configures freely (instance class, queue names, ACU within ceiling)

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

## Current Version: v2.1.0
