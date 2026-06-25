# ──────────────────────────────────────────────────────────────────────────────
# FILE: modules/openshift/rosa-hcp/security_groups.tf
# Module bump: v1.9.0 → v1.10.0
# ──────────────────────────────────────────────────────────────────────────────
#
# Optional: Custom Security Group for the ROSA HCP Control-Plane PrivateLink Endpoint.
#
# BACKGROUND
# ──────────
# ROSA HCP exposes the OpenShift API (port 443) via an AWS VPC Interface Endpoint
# (PrivateLink) created in the customer VPC. By default, AWS associates the VPC's
# default Security Group with the endpoint. This resource adds a CUSTOM, explicit
# SG that allows HTTPS from known internal bank networks, which is required for:
#   - On-prem access via TGW (10.0.0.0/8)
#   - Hub/Transit network (172.16.0.0/16)
#   - Spoke VPCs (172.27.0.0/16)
#
# REQUIREMENTS
# ────────────
#   - ROSA HCP >= 4.17.2 (fleet runs 4.20.25 ✅).
#   - var.cp_ingress_cidrs must be non-empty to activate. Default = [] (disabled).
#
# MECHANISM
# ─────────
#   1. Create aws_security_group with ingress rules for each CIDR on port 443.
#   2. Discover the PrivateLink endpoint ROSA creates in the VPC.
#   3. Associate the SG (additive — does NOT remove the default SG).
#
# TAG DISCOVERY NOTE
# ──────────────────
# ROSA HCP tags the API VPC endpoint with:
#   red-hat-managed       = "true"
#   api.openshift.com/id  = "<cluster_id>"   ← primary filter (cluster-scoped)
#
# ⚠️ If the plan fails on `data.aws_vpc_endpoint.rosa_api`, verify the tags
# against the actual endpoint AFTER int-dev cluster creation:
#
#   aws ec2 describe-vpc-endpoints \
#     --filters "Name=vpc-id,Values=<VPC_ID>" \
#               "Name=vpc-endpoint-type,Values=Interface" \
#               "Name=tag:red-hat-managed,Values=true" \
#     --query 'VpcEndpoints[].{Id:VpcEndpointId,Tags:Tags}' \
#     --output table
#
# If the tag key differs, update the filter below and document the correction.
#
# ⚠️ APPLY ORDERING:
# The VPC endpoint is created by ROSA during cluster provisioning.
# Because wait_for_create_complete = true is set in rhcs_cluster_rosa_hcp,
# the endpoint exists by the time Terraform finishes the cluster resource.
# The data source has depends_on = [rhcs_cluster_rosa_hcp.this] to enforce
# correct evaluation order within a single apply run.
# On a fresh cluster, a single `terragrunt apply` is sufficient.

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "rosa_cp" {
  # Only created when cp_ingress_cidrs is non-empty.
  count = length(var.cp_ingress_cidrs) > 0 ? 1 : 0

  name        = "sgp-aw-${local.region_short}-${var.cluster_name}-cp"
  description = "Additional SG for ROSA HCP Control-Plane PrivateLink endpoint. Allows HTTPS from bank internal networks. Managed by Terraform (rosa-hcp module v1.10.0)."
  vpc_id      = data.aws_vpc.rosa.id

  tags = merge(local.tags, {
    Name                              = "sgp-aw-${local.region_short}-${var.cluster_name}-cp"
    "bancointernacional.ec/component" = "rosa-hcp-cp-sg"
  })
}

# ── Ingress rules — one per allowed CIDR, all on port 443/tcp ─────────────────
#
# Uses the modern aws_vpc_security_group_ingress_rule (AWS provider >= 5.x, we
# run ~> 6.51) rather than inline ingress blocks, which enables independent
# lifecycle management of each rule.

resource "aws_vpc_security_group_ingress_rule" "rosa_cp_https" {
  for_each = length(var.cp_ingress_cidrs) > 0 ? toset(var.cp_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.rosa_cp[0].id
  description       = "HTTPS from ${each.key} — bank internal network (TGW/VPN reachable)."
  cidr_ipv4         = each.key
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.cluster_name}-cp-https-${replace(each.key, "/", "-")}"
  })
}

# ── Egress rule ───────────────────────────────────────────────────────────────
#
# Interface endpoints respond to inbound requests; they need to route responses
# back. Allow all egress so ROSA health checks and TLS handshakes complete.
# The endpoint is private — egress stays inside the VPC / TGW fabric.

resource "aws_vpc_security_group_egress_rule" "rosa_cp_all" {
  count = length(var.cp_ingress_cidrs) > 0 ? 1 : 0

  security_group_id = aws_security_group.rosa_cp[0].id
  description       = "Allow all egress. Required for ROSA HCP endpoint TLS responses and health checks."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # all protocols

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.cluster_name}-cp-egress-all"
  })
}

# ── Discover the ROSA HCP PrivateLink endpoint ────────────────────────────────
#
# ROSA creates one Interface VPC Endpoint per cluster in the customer VPC.
# Because our VPC naming convention ties one VPC to one cluster (discovered via
# the vpc_name_to_discover local), filtering by vpc_id + red-hat-managed + cluster
# ID is sufficient for unique identification.
#
# depends_on ensures Terraform defers reading this data source to apply time
# (after rhcs_cluster_rosa_hcp.this is created), rather than plan time.

data "aws_vpc_endpoint" "rosa_api" {
  count = length(var.cp_ingress_cidrs) > 0 ? 1 : 0

  vpc_id            = data.aws_vpc.rosa.id
  vpc_endpoint_type = "Interface"

  # Primary cluster-scoped filter. Verify the tag key against the actual endpoint
  # after first apply if the data source fails (see discovery note above).
  filter {
    name   = "tag:api.openshift.com/id"
    values = [rhcs_cluster_rosa_hcp.this.id]
  }

  filter {
    name   = "tag:red-hat-managed"
    values = ["true"]
  }

  # Only attach to an available endpoint (not pending/deleting).
  filter {
    name   = "vpc-endpoint-state"
    values = ["available"]
  }

  depends_on = [rhcs_cluster_rosa_hcp.this]
}

# ── Associate the custom SG with the PrivateLink endpoint ─────────────────────
#
# This association is ADDITIVE. The VPC default SG (or any SG AWS already
# associated) remains on the endpoint unchanged. ROSA internal traffic is
# not disrupted.
#
# replace_default_association = false (Terraform default) — keeps existing SGs.

resource "aws_vpc_endpoint_security_group_association" "rosa_cp" {
  count = length(var.cp_ingress_cidrs) > 0 ? 1 : 0

  vpc_endpoint_id   = data.aws_vpc_endpoint.rosa_api[0].id
  security_group_id = aws_security_group.rosa_cp[0].id
}
