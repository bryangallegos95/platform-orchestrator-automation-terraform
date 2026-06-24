# modules/openshift/rosa-hcp/main.tf
#
# PRIVATE ROSA HCP cluster + worker MachinePools (one per AZ, autoscaling always on).
#
# - Private (PrivateLink): no public API; access via TGW/VPN.
# - Subnets discovered by tag (data.tf). Cluster knows all pool AZs' subnets.
# - Machine CIDR derived from discovered VPC (locals.machine_cidr).
# - Account roles referenced by prefix; operator roles/OIDC are per-cluster (iam.tf).
#
# ⚠️ rhcs PROVIDER NOTE: argument names for rhcs_cluster_rosa_hcp can vary by
# provider minor. This targets ~> 1.6. Run `terraform validate` first; if an
# argument name differs the error will name it precisely (see validation runbook).

resource "rhcs_cluster_rosa_hcp" "this" {
  name                   = var.cluster_name
  cloud_region           = var.aws_region
  aws_account_id         = var.aws_account_id
  aws_billing_account_id = var.aws_account_id

  version = var.openshift_version

  # ── Private cluster (PrivateLink) ───────────────────────────────────────────
  private          = true
  aws_private_link = true

  # ── Networking ──────────────────────────────────────────────────────────────
  machine_cidr = local.machine_cidr   # = discovered VPC CIDR (auto-derived)
  pod_cidr     = var.pod_cidr
  service_cidr = var.service_cidr
  host_prefix  = var.host_prefix

  # Subnets discovered by tag — union of all pools' AZ subnets.
  aws_subnet_ids = local.cluster_subnet_ids

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

  # Initial compute hint; real scaling is governed by the machine pools below.
  replicas             = length(var.machine_pools)
  compute_machine_type = var.compute_machine_type

  tags = local.tags

  wait_for_create_complete = true

  depends_on = [
    module.operator_roles,
    module.oidc_config_and_provider,
    null_resource.account_guard,
  ]
}

# ── Worker MachinePools — HA via one pool per AZ, autoscaling always on ────────
resource "rhcs_hcp_machine_pool" "this" {
  for_each = { for mp in var.machine_pools : mp.name => mp }

  cluster = rhcs_cluster_rosa_hcp.this.id
  name    = each.value.name

  aws_node_pool = {
    instance_type = var.compute_machine_type
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
