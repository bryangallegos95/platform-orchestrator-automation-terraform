# Platform Orchestrator — Terraform Automation

> Centralized reusable workflows and Terraform modules for all IaC deployments across Banco Internacional's AWS multi-account organization.

**Current version:** `v2.1.0`

**Knowledge Base:** [bin-transversales-devops/platform-knowledge-base](https://github.com/bin-transversales-devops/platform-knowledge-base)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  This Repository (Platform Orchestrator)                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  .github/workflows/                                                 │
│  ├── ci.yml      ← Reusable CI: format → lint → plan → cost → PR   │
│  ├── cd.yml      ← Reusable CD: apply → rollback → promotion issue │
│  ├── release.yml ← Manual release: validate → tag → GH Release     │
│  └── emergency-cluster-ops.yml ← ROSA cluster emergency operations  │
│                                                                     │
│  modules/                                                           │
│  ├── compute/         (ec2)                                         │
│  ├── database/        (aurora-postgresql, elasticache-serverless)    │
│  ├── identity/        (irsa-role)                                   │
│  ├── integration/     (appflow, kinesis-firehose, s3-private)       │
│  ├── messaging/       (sqs)                                         │
│  ├── networking/      (centralized-endpoints, palo-alto-vmseries,   │
│  │                     vpc)                                          │
│  └── openshift/       (account-bootstrap, cluster-config, rosa-hcp) │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
         ▲                           ▲
         │  workflow_call             │  git::...?ref=v2.1.0
         │                           │
┌────────┴───────────┐    ┌──────────┴──────────────────────┐
│  Son Repo A        │    │  Son Repo B                      │
│  (Service X)       │    │  (Service Y)                     │
└────────────────────┘    └─────────────────────────────────┘
```

---

## Modules

| Category | Module | Description |
|----------|--------|-------------|
| **compute** | `ec2` | Single EC2 instance (IMDSv2, encrypted EBS, SSM-managed) |
| **database** | `aurora-postgresql` | Aurora PostgreSQL Serverless v2 (port 15432, CMK, IAM Auth, pgaudit) |
| **database** | `elasticache-serverless` | ElastiCache Serverless Valkey (TLS, IAM Auth) |
| **identity** | `irsa-role` | IRSA roles for ROSA pods (1:1 ServiceAccount enforcement) |
| **integration** | `appflow` | Amazon AppFlow connectors and flows |
| **integration** | `kinesis-firehose` | Kinesis Data Firehose delivery streams |
| **integration** | `s3-private` | Private S3 buckets with encryption and lifecycle |
| **messaging** | `sqs` | SQS queues with mandatory DLQ |
| **networking** | `centralized-endpoints` | Shared VPC Interface Endpoints |
| **networking** | `palo-alto-vmseries` | Palo Alto VM-Series firewall appliances |
| **networking** | `vpc` | Spoke VPC for Hub-and-Spoke topology (TGW attached) |
| **openshift** | `account-bootstrap` | AWS account baseline for ROSA |
| **openshift** | `cluster-config` | Day-2 ROSA cluster configuration |
| **openshift** | `rosa-hcp` | ROSA HCP cluster provisioning |

---

## Consuming Modules (Son Repo Usage)

Son repos reference modules from this repository via git source with a pinned version tag.

### Example — `terragrunt.hcl`

```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/identity/irsa-role?ref=v2.1.0"
}

inputs = {
  aws_region     = "us-east-1"
  service        = "pagos"
  workload       = "core"
  ambiente       = "prod"
  aws_account_id = "123456789012"
  oidc_issuer_url = dependency.rosa.outputs.oidc_endpoint_url

  roles = {
    sqs-producer = {
      service_accounts = [
        { namespace = "pagos", name = "pagos-sa" }
      ]
      description = "SQS producer for pagos service"
      inline_policies = {
        sqs-send = file("policies/sqs-send.json")
      }
    }
  }

  aplicacion          = "Pagos"
  propietario_recurso = "Equipo Pagos"
  producto            = "Banca Digital"
  centro_costo        = "CC-1234"
}
```

### Example — Reusable CI workflow call

```yaml
# .github/workflows/ci.yml (in son repo)
name: Terraform CI
on:
  push:
    branches: [dev, testing]

jobs:
  ci:
    uses: bin-transversales-devops/platform-orchestrator-automation-terraform/.github/workflows/ci.yml@v2.1.0
    with:
      environment: dev
      working_directory: environments/dev
      account_id: "123456789012"
      ou_name: pagos
    secrets: inherit
```

---

## Reusable Workflows

### `ci.yml` — Terraform CI

Called by son repos to validate infrastructure changes.

| Job | What it does |
|-----|-------------|
| Resolve | Derives region, S3 bucket, state key from environment |
| Format | `terragrunt hclfmt --check --diff` |
| Lint | `tflint` with pre-installed AWS plugin |
| Plan | `terragrunt validate` + `plan` with `-detailed-exitcode` |
| Cost | `infracost breakdown` (only if changes detected) |
| Security | Prowler IaC scan |
| Create PR | Auto-creates PR with plan output + `DEPLOYMENT_CONTEXT` metadata |

### `cd.yml` — Terraform CD

Called by son repos after PR merge to apply infrastructure changes.

| Job | What it does |
|-----|-------------|
| Resolve | Derives region, bucket, state key |
| Apply | Downloads saved plan → `terragrunt apply tfplan` |
| Promotion Issue | Creates GitHub Issue with `/approve` and `/reject` commands |

**Key behaviors:**
- Applies the **exact** plan binary from CI (no re-plan)
- Auto-rollback (destroy) in dev/qa on failure; alert-only in preprod/prod/dr
- Change window: prod blocked during Ecuador business hours (Mon-Fri 08:30-17:30 UTC-5)
- Promotion chain: dev → qa → preprod → prod → dr

### `release.yml` — Module Release

Manually triggered to create a versioned release.

| Step | What it does |
|------|-------------|
| Validate | Runs `terraform validate` on all modules |
| Tag | Creates annotated git tag (e.g. `v2.2.0`) |
| Release | Creates GitHub Release with auto-generated changelog |

**Usage:** Actions → Release → Run workflow → Enter version (e.g. `2.2.0`)

### `emergency-cluster-ops.yml` — ROSA Emergency Operations

Manually triggered for ROSA cluster emergency operations (hibernation, resume).

---

## Environment → Region → Bucket Mapping

| Environment | Region | State Bucket |
|-------------|--------|--------------|
| `dev` | `us-east-1` | `s3-aw-ue1-terraform-state-dev` |
| `qa` | `us-east-1` | `s3-aw-ue1-terraform-state-qa` |
| `preprod` | `us-east-1` | `s3-aw-ue1-terraform-state-preprod` |
| `prod` | `us-east-1` | `s3-aw-ue1-terraform-state-prod` |
| `dr` | `us-east-2` | `s3-aw-ue2-terraform-state-dr` |

---

## Three-Tier Hardening Contract

Every module follows a three-tier hardening contract:

| Tier | Rule | Examples |
|------|------|----------|
| **LOCKED** | Cannot be overridden | Encryption at rest/transit, TLS, non-default ports (15432, 6380), audit logging, max_session 3600s |
| **GUARD-RAIL** | Floor can be raised, never lowered | backup_retention (min 7d), ACU ceiling (256), monitoring_interval in prod, IRSA 1:1 SA |
| **FREE** | Freely configurable | instance_class, queue names, ACU within ceiling, database_name, extra_tags |

---

## Naming Convention

Pattern: `{TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}`

- **TIPO:** `s3`, `kdf`, `appflow`, `role`, `aurora`, `sqs`, `vpc`, `sg`...
- **UBICACION:** `aw` (AWS), `az` (Azure), `gc` (GCP)
- **REGION:** `ue1` (us-east-1), `ue2` (us-east-2), `glb` (global)
- **FUNCION:** 1-6 segments, lowercase alphanumeric + hyphens
- **AMBIENTE:** `dev`, `qa`, `preprod`, `prod`, `dr`

Example: `aurora-aw-ue1-payments-core-prod`

---

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

---

## Versioning & Releases

This repo uses **semantic versioning** via git tags. Son repos pin to a specific version.

| Tag | Meaning |
|-----|---------|
| `v2.1.0` | Current stable release |
| `vX.Y.0` | New features (backwards-compatible) |
| `vX+1.0.0` | Breaking changes (requires son repo updates) |

**Release process:**
1. Merge changes to `master`
2. Go to Actions → Release → Run workflow
3. Enter the new version (e.g. `2.2.0`)
4. The workflow validates all modules, creates the tag, and publishes a GitHub Release
5. Update son repos to reference the new tag: `?ref=v2.2.0`

---

## Contributing

1. Create a feature branch from `master`
2. Make changes to modules or workflows
3. Test with a son repo pointing to your branch: `?ref=feature/my-change`
4. Create a PR against `master`
5. After merge, trigger the Release workflow with the new version
6. Update son repos to reference the new tag

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                    # Reusable CI workflow
│       ├── cd.yml                    # Reusable CD workflow
│       ├── release.yml               # Release tagging workflow
│       └── emergency-cluster-ops.yml # ROSA emergency operations
├── modules/
│   ├── compute/
│   │   └── ec2/                      # EC2 instance (IMDSv2, encrypted, SSM)
│   ├── database/
│   │   ├── aurora-postgresql/        # Aurora PostgreSQL (15432, CMK, pgaudit)
│   │   └── elasticache-serverless/   # Valkey Serverless (TLS, IAM Auth)
│   ├── identity/
│   │   └── irsa-role/                # IRSA roles (1:1 SA enforcement)
│   ├── integration/
│   │   ├── appflow/                  # Amazon AppFlow
│   │   ├── kinesis-firehose/         # Kinesis Data Firehose
│   │   └── s3-private/              # Private S3 buckets
│   ├── messaging/
│   │   └── sqs/                      # SQS with mandatory DLQ
│   ├── networking/
│   │   ├── centralized-endpoints/    # Shared VPC Endpoints
│   │   ├── palo-alto-vmseries/       # Palo Alto firewalls
│   │   └── vpc/                      # Spoke VPC (Hub-and-Spoke, TGW)
│   └── openshift/
│       ├── account-bootstrap/        # AWS account baseline for ROSA
│       ├── cluster-config/           # ROSA day-2 configuration
│       └── rosa-hcp/                 # ROSA HCP cluster
├── scripts/
│   └── naming_pattern_validator.sh   # Enterprise naming validation
└── docs/
    └── dr-backing-services.md        # DR procedures
```

---

## Cross-Repo Dependencies

| This Repo Provides | Consumed By |
|---------------------|-------------|
| `modules/database/aurora-postgresql/` | Son repos needing Aurora |
| `modules/database/elasticache-serverless/` | Son repos needing Valkey cache |
| `modules/messaging/sqs/` | Son repos needing queues |
| `modules/identity/irsa-role/` | Son repos needing pod-level AWS access |
| `modules/integration/s3-private/` | Son repos needing private S3 |
| `.github/workflows/ci.yml` | All son repos (workflow_call) |
| `.github/workflows/cd.yml` | All son repos (workflow_call) |
| `scripts/naming_pattern_validator.sh` | CI lint step |

---

## Runner Requirements

| Requirement | Detail |
|-------------|--------|
| Image | `runner-gh-aws-terraform:2.0.0` |
| Pre-installed | Terraform 1.11.4, Terragrunt 0.69.10, TFLint 0.55.0, Infracost 0.10.40, gh CLI 2.65.0 |
| Labels | `self-hosted, linux, terraform, aws, {env}` |
| IAM | IRSA via `runner-pivot-role-{env}` → assumes `terraform-apply-role` in target |
