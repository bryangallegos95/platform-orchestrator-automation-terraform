# 🏗️ Platform Orchestrator — Terraform Automation

> Centralized reusable workflows and Terraform modules for all IaC deployments across Banco Internacional's AWS multi-account organization.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  This Repository (Platform Orchestrator)                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  .github/workflows/                                                 │
│  ├── ci.yml    ← Reusable CI: format → lint → plan → cost → PR     │
│  └── cd.yml    ← Reusable CD: apply → rollback → promotion issue   │
│                                                                     │
│  modules/                                                           │
│  ├── networking/                                                    │
│  │   └── vpc/  ← Spoke VPC module (Hub-and-Spoke topology)          │
│  ├── compute/                                                       │
│  │   └── ec2/  ← EC2 instance module (deploys into a Spoke VPC)     │
│  └── database/                                                      │
│      └── aurora-postgresql/ ← Aurora cluster (deploys into a Spoke) │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
         ▲                           ▲
         │  workflow_call             │  git::...?ref=v1.0.0
         │                           │
┌────────┴───────────┐    ┌──────────┴──────────────────────┐
│  Son Repo A        │    │  Son Repo B                      │
│  (VPC DatosAnalit) │    │  (VPC OtroProducto)              │
└────────────────────┘    └─────────────────────────────────┘
```

## Reusable Workflows

### `ci.yml` — Terraform CI

Called by son repos to validate infrastructure changes.

| Job | What it does |
|-----|-------------|
| ⓪ Resolve | Derives region, S3 bucket, state key from environment |
| ① Format | `terragrunt hclfmt --check --diff` |
| ② Lint | `tflint` with pre-installed AWS plugin |
| ③ Plan | `terragrunt validate` + `plan` with `-detailed-exitcode` |
| ④ Cost | `infracost breakdown` (only if changes detected) |
| ⑤ Create PR | Auto-creates PR with plan output + `DEPLOYMENT_CONTEXT` metadata |

**Key inputs:**

| Input | Required | Description |
|-------|----------|-------------|
| `environment` | ✅ | `dev`, `qa`, `preprod`, `prod`, `dr` |
| `working_directory` | ✅ | Path to terragrunt env (e.g. `environments/dev`) |
| `account_id` | ✅ | AWS account ID for the target environment |
| `ou_name` | ✅ | OU/product name — S3 state key prefix |
| `extra_vars` | ❌ | Space-separated `-var` overrides |
| `create_pr` | ❌ | Whether to auto-create a PR (default: `true`) |
| `pr_source_branch` | ❌ | Source branch for PR |
| `pr_target_branch` | ❌ | Target branch for PR |
| `dev_account_id` | ❌ | Passthrough for promotion chain |
| `qa_account_id` | ❌ | Passthrough for promotion chain |
| `preprod_account_id` | ❌ | Passthrough (empty = skip preprod) |
| `prod_account_id` | ❌ | Passthrough for promotion chain |
| `dr_enabled` | ❌ | Enable DR deploy in us-east-2 |
| `feature_branch` | ❌ | Original feature branch for traceability |

**Key outputs:**

| Output | Description |
|--------|-------------|
| `plan_exitcode` | `0` = no changes, `2` = changes detected |
| `plan_artifact_name` | Artifact name for CD to download |
| `pr_number` | PR number if created |
| `pr_url` | PR URL if created |

---

### `cd.yml` — Terraform CD

Called by son repos after PR merge to apply infrastructure changes.

| Job | What it does |
|-----|-------------|
| ⓪ Resolve | Derives region, bucket, state key |
| ① Apply | Downloads saved plan → `terragrunt apply tfplan` |
| ② Promotion Issue | Creates GitHub Issue with `/approve` and `/reject` commands |

**Key behaviors:**

| Behavior | Detail |
|----------|--------|
| No re-plan | Applies the **exact** plan binary from CI |
| Skip if no changes | `plan_exitcode=0` → apply skipped entirely |
| Rollback (dev/qa) | Auto-destroy on apply failure |
| Rollback (preprod/prod/dr) | Alert only — manual intervention required |
| Change window | Prod: Mon–Fri, 12:00–22:00 UTC only |
| Concurrency | Queued (never cancels a running apply) |
| Promotion | Creates issue with `PROMOTION_METADATA` for next environment |

---

## Modules

### `modules/networking/vpc`

Spoke VPC for Hub-and-Spoke topology with Transit Gateway.

**Creates:**
- VPC with configurable CIDR
- 6 private subnets (app × 2 AZs, bdd × 2 AZs, gwlb × 2 AZs)
- TGW VPC attachment (app subnets)
- Route tables (1 per AZ, default route → TGW)
- VPC Flow Logs → CloudWatch

**Does NOT create (lives in Hub account):**
- Transit Gateway itself
- NAT Gateway / IGW
- Hub route tables

**Required variables:**

| Variable | Type | Description |
|----------|------|-------------|
| `aws_region` | string | `us-east-1` or `us-east-2` (DR) |
| `service` | string | Short product name (e.g. `datosanalitica`) |
| `ambiente` | string | `dev`, `qa`, `preprod`, `prod`, `dr` |
| `vpc_cidr` | string | VPC CIDR block |
| `subnet_*_cidr` | string | 6 subnet CIDRs |
| `tgw_id` | string | Transit Gateway ID |
| `aplicacion` | string | Mandatory tag |
| `propietario_recurso` | string | Mandatory tag |
| `producto` | string | Mandatory tag |
| `centro_costo` | string | Mandatory tag |

**Usage (from son repo's `terragrunt.hcl`):**
```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/networking/vpc?ref=v1.0.0"
}
```

---

### `modules/compute/ec2`

Single EC2 instance deployed into an existing Spoke VPC. One module call = one instance (use `workload` to distinguish them: `bastion`, `sftp`, `app01`…).

**Creates:**
- EC2 instance in a discovered private subnet (`subnet_tier` = app/bdd/gwlb, `subnet_az` = a/b)
- Dedicated Security Group (no inbound by default — access via SSM Session Manager)
- IAM role + instance profile with `AmazonSSMManagedInstanceCore`

**Discovery (no IDs passed in, no shared state):**
- VPC by Name convention: `vpc-aw-{region}-{service}-{ambiente}`
- Subnet by the `Tier` / `AZ` tags stamped by the VPC module

**Hardening baked in:**
- IMDSv2 required by default, root EBS always encrypted (optional CMK via `ebs_kms_key_arn`)
- No public IP, EBS-optimized, termination protection auto-enabled in preprod/prod/dr
- AMI resolved from SSM parameter (latest AL2023 by default) and pinned at creation — upgrades are deliberate via `ami_id`

**Required variables:**

| Variable | Type | Description |
|----------|------|-------------|
| `service` | string | Must match the Spoke VPC's `service` (drives discovery) |
| `workload` | string | Name suffix of this instance (e.g. `bastion`) |
| `ambiente` | string | `dev`, `qa`, `preprod`, `prod`, `dr` |
| `aws_account_id` | string | Target account — guardrail against wrong-account applies |
| `aplicacion` | string | Mandatory tag |
| `propietario_recurso` | string | Mandatory tag |
| `producto` | string | Mandatory tag |
| `centro_costo` | string | Mandatory tag |

**Key optional variables:** `instance_type` (default `t3.medium`), `subnet_tier`/`subnet_az`, `ami_id`, `root_volume_size`, `ebs_kms_key_arn`, `ingress_rules`, `additional_iam_policy_arns`, `user_data`, `extra_tags`.

**Usage (from son repo's `terragrunt.hcl`):**
```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/compute/ec2?ref=v1.13.0"
}
```

---

### `modules/database/aurora-postgresql`

Aurora PostgreSQL cluster deployed into an existing Spoke VPC (BDD tier). One module call = one cluster (use `workload` to distinguish them: `core`, `ledger`, `clientes`…).

**Creates:**
- DB subnet group over the discovered BDD-tier subnets (both AZs)
- Aurora PostgreSQL cluster + instances (map-driven — son repos add readers or change the class without module changes)
- Cluster + instance parameter groups (TLS forced, pgaudit, slow-query logging — **security baseline locked**)
- Dedicated Security Group (no inbound by default — **15432/tcp** opt-in per consumer)
- Managed CloudWatch log group for the PostgreSQL export (retention by env + CMK `alias/CWLogs`)
- Enhanced Monitoring IAM role (prod-like envs)
- Additive KMS grants for consumer workload roles (`aws_kms_grant` — never touches the key policy)

**Discovery (no IDs passed in, no shared state):**
- VPC by Name convention: `vpc-aw-{region}-{service}-{ambiente}`
- BDD subnets by the `Tier=bdd` / `AZ` tags stamped by the VPC module
- RDS CMK by alias (`kms_key_alias`, default `alias/RDS`) + CloudWatch Logs CMK (`alias/CWLogs`) — the keys **already exist** in every account (account baseline); the module never creates keys

**Port:** the cluster listens on **15432** (platform security standard, `🔒 LOCKED`), not the PostgreSQL default 5432. Consumers must target `:15432`.

**Topology by environment:**

| Environment | Default topology |
|-------------|-----------------|
| dev / qa / preprod | Single-AZ — 1 writer (may opt UP to multi-AZ) |
| prod / dr | Multi-AZ — writer (AZ-a) + reader (AZ-b), auto-failover — `🔒 LOCKED` (cannot downgrade) |
| dr (Global DB) | opt-in Aurora Global Database replication (`enable_global_database` on prod + `global_cluster_identifier` on dr) |

**Compute model (orthogonal to topology):**

| Model | How | Notes |
|-------|-----|-------|
| Provisioned (default) | `instance_class` (default `db.r6g.large`) | Fixed capacity |
| Serverless v2 | `serverless = true` + `serverless_min_acu` / `serverless_max_acu` | Instances become `db.serverless`; scales in ACUs (1 ACU ≈ 2 GiB) |
| Serverless v2 + auto-pause | `serverless_min_acu = 0` | Compute cost $0 while idle, ~15s resume. **dev/qa only** — blocked by precondition in preprod/prod/dr. Requires engine 16.3+/15.7+/14.12+ (enforced at plan time) |

**Hardening contract — 3 layers (see `modules/database/aurora-postgresql/README.md`):**

`🔒 LOCKED` (invariant, identical in every env, a son repo CANNOT change):
- Storage encryption with the account CMK (`alias/RDS`), IAM database authentication, `rds.force_ssl=1`
- pgaudit + connection/DDL logging baseline (protected — son overrides of these parameter names are rejected)
- Not publicly accessible, `allow_major_version_upgrade=false`, `copy_tags_to_snapshot`, port **15432**
- `engine_version` allow-list (major ≥ 14 — EOL engines rejected)

`🛡️ GUARD-RAIL` (env FLOOR a son repo may RAISE but never LOWER):
- Multi-AZ (prod/dr), Enhanced Monitoring (prod-like ≥ 60s), `apply_immediately=false` (prod-like)
- PITR backup retention floor: 35 days prod/dr, 7 elsewhere
- Deletion protection: locked ON in preprod/prod/dr; default ON in dev/qa (a son repo sets `false` only for ephemeral clusters)
- Serverless `max_acu` ceiling per env (dev/qa 8, preprod 16, prod/dr 64)
- CloudWatch log retention: 30d dev/qa · 90d preprod · 365d prod/dr

`🎚️ FREE` (son-repo self-service within the guard rails): ACUs under the ceiling, extra readers, `database_name`, allowed consumers, non-baseline parameters, `storage_type` (FinOps: `aurora-iopt1`), tags.

**Admin service user (day-1/day-2):**
- `master_username` (default `svcadmin`) is the cluster admin service user
- Its password lives in **BeyondTrust Secrets Safe** (per-env vault) and is injected at plan time by `ci.yml` via the existing `secret_titles` input → `TF_VAR_master_password`. Never hardcoded, never a default
- Plan-time guardrail fails if the credential was not injected

**Required variables:**

| Variable | Type | Description |
|----------|------|-------------|
| `service` | string | Must match the Spoke VPC's `service` (drives discovery) |
| `workload` | string | Name suffix of this cluster (e.g. `core`) |
| `ambiente` | string | `dev`, `qa`, `preprod`, `prod`, `dr` |
| `aws_account_id` | string | Target account — guardrail against wrong-account applies |
| `master_password` | string | Injected via `TF_VAR_master_password` from BeyondTrust |
| `aplicacion` | string | Mandatory tag |
| `propietario_recurso` | string | Mandatory tag |
| `producto` | string | Mandatory tag |
| `centro_costo` | string | Mandatory tag |

**Key optional variables:** `engine_version` (default `16.6`, major ≥ 14), `db_family` (derived from major version), `instance_class` (default `db.r6g.large`), `serverless` / `serverless_min_acu` / `serverless_max_acu` / `serverless_auto_pause_seconds` (Serverless v2), `storage_type` (`standard` | `aurora-iopt1` — FinOps), `instances` (explicit topology map), `multi_az` (opt-UP only), `allowed_security_group_ids` / `allowed_cidrs` (15432 ingress), `kms_key_alias` (default `alias/RDS`) / `kms_key_arn`, `cloudwatch_logs_kms_key_alias` (default `alias/CWLogs`) / `cloudwatch_log_retention_days`, `kms_consumer_role_arns`, `cluster_parameters` / `instance_parameters` (non-baseline only), `enable_global_database` / `global_cluster_identifier`, `database_name`, `backup_retention_period` (floor-guarded), `extra_tags`.

**Usage (from son repo's `terragrunt.hcl`):**
```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/database/aurora-postgresql?ref=v1.14.0"
}
```

---

## Environment → Region → Bucket Mapping

| Environment | Region | Runner Tag | State Bucket |
|-------------|--------|------------|--------------|
| `dev` | `us-east-1` | `[self-hosted, terraform, dev]` | `s3-aw-ue1-terraform-state-dev` |
| `qa` | `us-east-1` | `[self-hosted, terraform, qa]` | `s3-aw-ue1-terraform-state-qa` |
| `preprod` | `us-east-1` | `[self-hosted, terraform, preprod]` | `s3-aw-ue1-terraform-state-preprod` |
| `prod` | `us-east-1` | `[self-hosted, terraform, prod]` | `s3-aw-ue1-terraform-state-prod` |
| `dr` | `us-east-2` | `[self-hosted, terraform, dr]` | `s3-aw-ue2-terraform-state-dr` |

## Branch → Environment Mapping (Son Repos)

| Branch | Environment | Purpose |
|--------|-------------|---------|
| `dev` | dev | Development |
| `testing` | qa | Quality Assurance |
| `preprod` | preprod | Pre-production (optional) |
| `master` | prod | Production |

---

## Runner Requirements

| Requirement | Detail |
|-------------|--------|
| Image | `runner-gh-aws-terraform:2.0.0` |
| Pre-installed tools | Terraform 1.11.4, Terragrunt 0.69.10, TFLint 0.55.0, Infracost 0.10.40, gh CLI 2.65.0 |
| Labels | `self-hosted,linux,terraform,aws,{env}` |
| Runner group | `aws-{env}` |
| IAM | IRSA via `runner-pivot-role-{env}` → assumes `terraform-apply-role` in target account |

---

## Promotion Flow

```
Port.io → orchestrator.yml → ci.yml (plan DEV, create PR)
  └── PR merged → cd-on-merge.yml → cd.yml (apply DEV)
      └── Promotion issue → /approve → ci.yml (plan QA, create PR)
          └── PR merged → cd.yml (apply QA)
              └── Promotion issue → /approve → ci.yml (plan PROD)
                  └── PR merged → cd.yml (apply PROD)
                      └── DR plan + apply (if enabled)
                          └── Lifecycle complete ✅
```

---

## Versioning

This repo uses **semantic versioning** via git tags.

| Tag | Impact |
|-----|--------|
| `v1.0.0` | Initial VPC module release |
| `v1.1.0` | New features (backwards-compatible) |
| `v2.0.0` | Breaking changes (requires son repo updates) |

Son repos pin to a specific version: `?ref=v1.0.0`

---

## Contributing

1. Create a feature branch from `master`
2. Make changes to modules or workflows
3. Test with a son repo pointing to your branch: `?ref=feature/my-change`
4. Create a PR against `master`
5. After merge, create a new tag: `git tag v1.x.x && git push origin v1.x.x`
6. Update son repos to reference the new tag

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml          # Reusable CI workflow
│       └── cd.yml          # Reusable CD workflow
└── modules/
    ├── compute/
    │   └── ec2/
    │       ├── main.tf             # EC2 instance (IMDSv2, encrypted root volume)
    │       ├── data.tf             # VPC/subnet discovery by tags + account guard
    │       ├── security_groups.tf  # Dedicated SG (no inbound by default)
    │       ├── iam.tf              # Instance role + profile (SSM core)
    │       ├── variables.tf        # All inputs with validations
    │       ├── outputs.tf          # Instance ID, private IP, SG ID, role ARN
    │       ├── locals.tf           # Naming conventions, tags
    │       └── versions.tf         # Provider constraints
    ├── database/
    │   └── aurora-postgresql/
    │       ├── main.tf              # Cluster, instances, subnet group, global DB
    │       ├── data.tf              # VPC/BDD-subnet/KMS (RDS+CWLogs) discovery
    │       ├── guards.tf            # terraform_data plan-time guards (account + region)
    │       ├── logs.tf              # Managed PostgreSQL log group (retention + CMK)
    │       ├── parameter_groups.tf  # Cluster/instance PGs (TLS, pgaudit baseline)
    │       ├── security_groups.tf   # Dedicated SG (no inbound by default, 15432)
    │       ├── iam.tf               # Enhanced Monitoring role
    │       ├── kms.tf               # Additive grants for consumer roles
    │       ├── variables.tf         # All inputs with validations (hardening contract)
    │       ├── outputs.tf           # Endpoints, resource ID, SG ID, KMS ARN, log group
    │       ├── locals.tf            # Naming, LOCKED/GUARD-RAIL contract, tags
    │       └── versions.tf          # Provider constraints
    └── networking/
        └── vpc/
            ├── main.tf         # VPC, subnets, TGW attachment, routes
            ├── variables.tf    # All inputs with validations
            ├── outputs.tf      # VPC ID, subnet IDs, TGW attachment ID
            ├── locals.tf       # Naming conventions, tags, AZ mapping
            └── versions.tf     # Provider constraints
```
