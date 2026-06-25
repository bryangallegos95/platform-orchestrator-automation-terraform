# modules/openshift/rosa-hcp/main.tf
#
# PRIVATE ROSA HCP cluster + worker MachinePools (one per AZ, autoscaling always on).
#
# - Private (PrivateLink): no public API; access via TGW/VPN.
# - Subnets discovered by tag (data.tf). Cluster knows all pool AZs' subnets.
# - Machine CIDR derived from discovered VPC (locals.machine_cidr).
# - Account roles referenced by prefix; operator roles/OIDC are per-cluster (iam.tf).
#
# ── MACHINE POOL NAMING CONTRACT (v1.9.0, fleet-critical) ────────────────────
# The first entry in var.machine_pools MUST be named "worker".
# "worker" is the name ROSA reserves for the auto-created default pool; the
# rhcs provider recognises it and fires "magic import": instead of creating a
# second pool, it adopts the existing default into Terraform state.
#
# Effect:
#   Greenfield cluster  → 1 apply, 1 pool, 0 orphans. Clean.
#   int-dev migration   → destroys "workers-small" (bad config), imports "worker"
#                         (correct config from cluster-level args). See runbook.
#
# Multi-AZ (prod/dr): first pool "worker" (AZ-a, magic import) + "worker-b"
# (AZ-b, explicit creation). Only "worker" may be named "worker".
#
# ⚠️ rhcs PROVIDER NOTE: argument names for rhcs_cluster_rosa_hcp can vary by
# provider minor. This targets ~> 1.6.2. Run `terraform validate` first; any
# name mismatch is reported precisely in the error output.

resource "rhcs_cluster_rosa_hcp" "this" {
  name                   = var.cluster_name
  cloud_region           = var.aws_region
  aws_account_id         = var.aws_account_id
  aws_billing_account_id = var.aws_account_id

  version = var.openshift_version

  # Explicitly set the creator ARN so it does not depend on provider
  # auto-derivation (which changed/regressed in rhcs 1.7.x). Uses the
  # caller identity the provider runs as (the assumed terraform-apply-role).
  properties = {
    rosa_creator_arn = local.rosa_creator_arn
  }

  # ── Private cluster (PrivateLink implied by private=true + private subnets) ──
  private = true

  # ── Networking ──────────────────────────────────────────────────────────────
  machine_cidr = local.machine_cidr   # = discovered VPC CIDR (auto-derived)
  pod_cidr     = var.pod_cidr
  service_cidr = var.service_cidr
  host_prefix  = var.host_prefix

  # Subnets discovered by tag — union of all pool AZ subnets.
  aws_subnet_ids = local.cluster_subnet_ids

  # AZs the cluster spans — derived from the same discovered pool subnets.
  availability_zones = local.cluster_availability_zones

  # ── Security / instance hardening ───────────────────────────────────────────
  # These two args configure the default "worker" pool AT CLUSTER CREATION TIME.
  # After creation they become irrelevant for Terraform (the pool-level resource
  # takes ownership). They MUST match the values set in aws_node_pool below so
  # that OCM state and Terraform state agree — preventing perpetual plan drift.
  #
  # IMDSv2 only (session-oriented, prevents SSRF credential theft). Bank standard.
  ec2_metadata_http_tokens = var.ec2_metadata_http_tokens

  # Worker root disk size (GiB). Fleet standard: 120 GiB (not ROSA's 300 default).
  worker_disk_size = var.worker_disk_size

  # ── STS / IAM wiring ────────────────────────────────────────────────────────
  sts = {
    operator_role_prefix = var.cluster_name
    role_arn             = "arn:aws:iam::${var.aws_account_id}:role/${var.account_role_prefix}-HCP-ROSA-Installer-Role"
    support_role_arn     = "arn:aws:iam::${var.aws_account_id}:role/${var.account_role_prefix}-HCP-ROSA-Support-Role"
    instance_iam_roles = {
      worker_role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.account_role_prefix}-HCP-ROSA-Worker-Role"
    }
    oidc_config_id = module.oidc_config_and_provider.oidc_config_id
  }

  # replicas seeds the default "worker" pool size at creation.
  # After creation, autoscaling on the rhcs_hcp_machine_pool resource governs this.
  replicas             = sum([for mp in var.machine_pools : mp.min_replicas])
  compute_machine_type = var.compute_machine_type

  tags = local.tags

  wait_for_create_complete = true

  depends_on = [
    module.operator_roles,
    module.oidc_config_and_provider,
    null_resource.account_guard,
  ]
}

# ── Worker MachinePools — one per AZ, autoscaling always on ──────────────────
#
# NAMING CONTRACT: the first pool MUST be named "worker" (see file header).
#
# IMMUTABILITY WARNING: disk_size and ec2_metadata_http_tokens inside
# aws_node_pool are IMMUTABLE after pool creation (rhcs provider constraint).
# Any change to these fields forces pool replacement (destroy + create).
# Always review the plan output before applying — especially on prod/dr.
#
# WHY we pin disk_size and ec2_metadata_http_tokens here:
#   Without explicit values, OCM applies its own hardcoded defaults:
#     disk_size                = 300 GiB   (ROSA default — 2.5x our standard)
#     ec2_metadata_http_tokens = "optional" (IMDSv1+v2 — violates bank standard)
#   Pinning them here ensures every machine pool the module creates matches the
#   bank security baseline regardless of OCM upstream defaults changing.
resource "rhcs_hcp_machine_pool" "this" {
  for_each = { for mp in var.machine_pools : mp.name => mp }

  cluster     = rhcs_cluster_rosa_hcp.this.id
  name        = each.value.name
  auto_repair = true

  aws_node_pool = {
    instance_type = var.compute_machine_type

    # Explicit pins — immutable post-creation.
    # Values MUST match the cluster-level ec2_metadata_http_tokens /
    # worker_disk_size args set above (OCM uses cluster args to bootstrap
    # the default pool; after that the pool resource governs). A mismatch
    # between these two levels causes perpetual plan drift on the "worker" pool.
    disk_size                = var.worker_disk_size
    ec2_metadata_http_tokens = var.ec2_metadata_http_tokens
  }

  # Pin this pool to ONE discovered subnet (one AZ).
  subnet_id = local.subnet_by_az[each.value.subnet_az]

  autoscaling = {
    enabled      = true
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas
  }

  depends_on = [rhcs_cluster_rosa_hcp.this]
}
