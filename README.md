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
│  └── networking/                                                    │
│      └── vpc/  ← Spoke VPC module (Hub-and-Spoke topology)          │
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
    └── networking/
        └── vpc/
            ├── main.tf         # VPC, subnets, TGW attachment, routes
            ├── variables.tf    # All inputs with validations
            ├── outputs.tf      # VPC ID, subnet IDs, TGW attachment ID
            ├── locals.tf       # Naming conventions, tags, AZ mapping
            └── versions.tf     # Provider constraints
```
