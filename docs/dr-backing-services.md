# Disaster Recovery — Backing Services Modules

This document describes the DR strategy for the backing-services modules in
`platform-orchestrator-automation-terraform`. It is intended for son repos
(e.g. `iac-tfn-backing-services-contenedores`) that deploy Aurora, SQS,
ElastiCache, and IRSA roles for containerized microservices on ROSA HCP.

## Architecture Context

```
PROD (us-east-1)                        DR (us-east-2)
┌──────────────────────┐                ┌──────────────────────┐
│  Aurora (primary)     │───Global DB───▶│  Aurora (secondary)   │
│  SQS queues (active)  │                │  SQS queues (standby) │
│  ElastiCache (active) │                │  ElastiCache (standby)│
│  IRSA roles (active)  │                │  IRSA roles (standby) │
└──────────────────────┘                └──────────────────────┘
         ▲                                        ▲
         │                                        │
    ROSA HCP (prod)                          ROSA HCP (dr)
    Cluster: biz-prod                        Cluster: biz-dr
```

## DR Model: Warm Standby

All resources are **pre-created** in the DR region/account. When disaster
strikes, only the application routing needs to switch (DNS/TGW failover).
The infrastructure is already in place.

| Service | DR State | Activation Required |
|---------|----------|---------------------|
| Aurora | Secondary (read-only, real-time replication) | Promote to standalone |
| SQS | Empty queues (ready to receive) | None — pods write on arrival |
| ElastiCache | Empty cache (Serverless, $0 idle) | None — cache warms on use |
| IRSA | Roles ready (bound to DR cluster OIDC) | None — pods assume on arrival |

## Per-Service DR Details

### 1. Aurora PostgreSQL — Global Database

**Mechanism**: Aurora Global Database (storage-level replication, RPO ~1 second).

**How it works**:
- PROD creates the Global Database (`enable_global_database = true`)
- DR joins as a read-only secondary (`global_cluster_identifier = "gdb-aw-..."`)
- Replication is at the storage level — no binlog, no logical replication
- The secondary cluster in DR is fully functional for reads immediately

**Cross-account support** (when DR uses a different AWS account):
- Set `source_account_id` to the PROD account ID in the DR environment config
- The module constructs the Global Cluster ARN for cross-account membership
- Prerequisite: the primary account must authorize the DR account via the RDS
  console → Global Database → "Add AWS accounts" or via API

**Failover procedure**:
```bash
# Planned failover (zero data loss, coordinated switchover):
aws rds switchover-global-cluster \
  --global-cluster-identifier gdb-aw-<service>-<workload> \
  --target-db-cluster-identifier arn:aws:rds:us-east-2:<dr-account>:cluster:rds-aw-ue2-<service>-<workload>-dr

# Unplanned failover (potential data loss of ~1s of writes):
aws rds failover-global-cluster \
  --global-cluster-identifier gdb-aw-<service>-<workload> \
  --target-db-cluster-identifier arn:aws:rds:us-east-2:<dr-account>:cluster:rds-aw-ue2-<service>-<workload>-dr
```

**Son repo configuration**:
```hcl
# environments/prod/aurora/terragrunt.hcl
inputs = {
  enable_global_database = true
  # ... other prod inputs
}

# environments/dr/aurora/terragrunt.hcl
inputs = {
  global_cluster_identifier = "gdb-aw-negocio-core"
  # Only needed if DR account differs from PROD account:
  # source_account_id = "761018868392"
  aws_region = "us-east-2"
  # ... other DR inputs (same as prod for engine, tags)
}
```

**RPO**: ~1 second | **RTO**: 1-2 minutes

---

### 2. SQS — Active Recreation (Empty Queues)

**Mechanism**: No native cross-region replication. Queues are pre-created
empty in us-east-2.

**Why this is acceptable**:
- SQS messages are ephemeral (notifications, events)
- Producers (BFFs) can retry on the new region's queues
- Messages in-flight at disaster time are lost (acceptable for this use case)
- If RPO ~0 is needed for messaging, use Amazon EventBridge Global Endpoints

**How it works**:
- The same module creates identical queues in DR (`ambiente = "dr"`)
- Naming: `sqs-aw-ue2-<service>-<workload>-<queue>-dr`
- Same CMK encryption (using the DR account's `alias/SQS` key)
- Same queue policies (deny non-TLS, deny non-owner)

**No activation required**: When ROSA DR pods start, they write/read from
the DR queues automatically (the queue URL is injected via env vars or
ConfigMap, derived from the naming convention + region).

**Son repo configuration**:
```hcl
# environments/dr/sqs/terragrunt.hcl
inputs = {
  # Same queue definitions as prod — only region/account differs
  queues = {
    notificaciones = { ... }  # same as prod
  }
  aws_region = "us-east-2"
  # ... mandatory tags, service, workload, ambiente = "dr"
}
```

**RPO**: N/A (messages in-flight are lost) | **RTO**: 0 (queues already exist)

---

### 3. ElastiCache Serverless — Warm Standby (Empty Cache)

**Mechanism**: Pre-created Serverless cache in us-east-2. No cross-region
replication (Global Datastore is not supported for Serverless as of 2026).

**Why this is acceptable**:
- Cache is ephemeral — the source of truth is Aurora (which HAS RPO ~1s)
- Cold start adds ~5-15 seconds of extra latency while cache warms
- Serverless = $0 cost when idle (no traffic in DR = no charges)
- Data rebuilds automatically from Aurora when pods start querying

**How it works**:
- Same module creates an identical Serverless cache in DR
- Naming: `ec-aw-ue2-<service>-<workload>-dr`
- VPC/subnets discovered by tag in the DR VPC
- Same CMK encryption (DR account's `alias/ElastiCache`)
- Same SG rules (consumers must exist in DR VPC)

**No activation required**: Cache exists, warms on first request.

**If you need RPO ~0 for cache** (e.g. critical session data):
- Option: Switch to node-based ElastiCache with Global Datastore
- Trade-off: Pay for idle nodes in DR + lose auto-scaling
- Recommendation: Store session state in Aurora (which has Global DB)
  and use cache as a read-through layer only

**Son repo configuration**:
```hcl
# environments/dr/redis/terragrunt.hcl
inputs = {
  engine               = "valkey"
  major_engine_version = "8"
  aws_region           = "us-east-2"
  # Same usage limits as prod
  # ... mandatory tags, service, workload, ambiente = "dr"
}
```

**RPO**: N/A (cache is ephemeral) | **RTO**: 0 (cache exists, cold start ~15s)

---

### 4. IRSA Roles — Recreated with DR Cluster OIDC

**Mechanism**: IAM roles are pre-created in the DR account, trusting the
DR cluster's OIDC provider.

**Key difference from prod**:
- The `oidc_issuer_url` is DIFFERENT (it belongs to the DR ROSA cluster)
- The IAM role ARNs are different (different account, different region prefix)
- The inline policies reference DR-region resource ARNs

**How it works**:
- Same module discovers the OIDC provider in the DR account
  (`data.aws_iam_openid_connect_provider` finds the DR cluster's OIDC)
- Roles are named: `irsa-aw-ue2-<service>-<workload>-<context>-dr`
- Trust policies point to the DR cluster's OIDC issuer
- Inline policies reference DR resource ARNs (`us-east-2`, DR account)

**No activation required**: Roles exist, pods assume them on arrival.

**Son repo configuration**:
```hcl
# environments/dr/irsa/terragrunt.hcl
inputs = {
  # OIDC from the DR ROSA cluster (different from prod!)
  oidc_issuer_url = "rh-oidc.s3.us-east-1.amazonaws.com/<dr-cluster-oidc-id>"
  aws_region      = "us-east-2"

  roles = {
    sqs-producer = {
      service_accounts = [ ... ]  # Same SAs as prod
      inline_policies = {
        # ARNs point to DR resources (us-east-2, DR account)
        sqs-send = "{ ... arn:aws:sqs:us-east-2:<dr-account>:sqs-aw-ue2-* ... }"
      }
    }
    # ... other roles
  }
}
```

**RPO**: N/A (IAM is infrastructure) | **RTO**: 0 (roles already exist)

---

## DR Pipeline Integration

The son repo's `cd-on-merge.yml` workflow handles DR automatically:

```
PROD apply succeeds
  └─▶ if dr_enabled == true:
        ├─ DR Prepare (resolve DR account, region, extra_vars)
        ├─ DR CI (plan in us-east-2 with DR account role)
        └─ DR CD (apply — creates/updates all DR resources)
```

This is the same pattern already validated in `iac-tfn-aurora-postgresql-contenedores`.
The workflow resolves the DR account from Port.io inputs (no `accounts.yaml` needed).

## DR Cost Summary (Warm Standby, Idle)

| Service | Monthly DR Cost (idle) | Notes |
|---------|----------------------|-------|
| Aurora Serverless (secondary) | ~$0.10/GB storage only | No ACU cost when secondary |
| SQS (empty queues) | $0 | No messages = no charges |
| ElastiCache Serverless | $0 | No traffic = no ECPU charges |
| IRSA roles | $0 | IAM is free |
| **Total** | **~$0.10/GB of DB storage** | Extremely cost-effective |

## Failover Checklist

1. [ ] Verify DR resources are healthy (Aurora secondary replicating, caches exist)
2. [ ] Promote Aurora secondary to standalone (or switchover Global DB)
3. [ ] Update DNS / Route53 / TGW routing to point to DR VPC
4. [ ] Activate ROSA DR cluster (if not already running)
5. [ ] Verify pods in DR can reach all backing services
6. [ ] Monitor DLQ depths and cache hit rates during warm-up

## Failback Procedure

After the primary region recovers:

1. [ ] Re-establish Aurora Global Database (create new secondary in us-east-1)
2. [ ] Wait for replication to catch up (minutes to hours depending on data volume)
3. [ ] Switch traffic back to us-east-1 (reverse of failover)
4. [ ] SQS/ElastiCache: no action needed (pods just start using primary region)
5. [ ] Verify prod cluster healthy, decommission DR secondary if desired
