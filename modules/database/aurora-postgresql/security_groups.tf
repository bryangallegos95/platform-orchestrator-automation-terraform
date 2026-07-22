# modules/database/aurora-postgresql/security_groups.tf
#
# Dedicated Security Group for the cluster.
#
# Default posture: NO inbound rules. Consumers (lambda/ecs/eks/ec2) are granted
# access explicitly, per workload, via:
#   - var.allowed_security_group_ids → SG-to-SG rules (preferred: identity of
#     the consumer, not its network location)
#   - var.allowed_cidrs              → CIDR rules (e.g. app-tier subnets)
# Both open ONLY the platform DB port (15432) — not configurable at the SG level.
#
# Uses the modern aws_vpc_security_group_ingress_rule / _egress_rule resources
# (AWS provider >= 5.x) rather than inline blocks, which enables independent
# lifecycle management of each rule.

resource "aws_security_group" "this" {
  name        = local.sg_name
  description = "SG for ${local.cluster_name}. Default: no inbound. ${local.db_port}/tcp opt-in per consumer. Managed by Terraform (database/aurora-postgresql module)."
  vpc_id      = data.aws_vpc.spoke.id

  tags = merge(local.tags, { Name = local.sg_name })
}

# ── Ingress — SG-to-SG (one rule per consumer Security Group) ────────────────
resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL (${local.db_port}) from consumer SG ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = local.db_port
  to_port                      = local.db_port
  ip_protocol                  = "tcp"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-${each.value}"
  })
}

# ── Ingress — CIDR (one rule per entry) ───────────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = {
    for r in var.allowed_cidrs : r.cidr => r
  }

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  cidr_ipv4         = each.value.cidr
  from_port         = local.db_port
  to_port           = local.db_port
  ip_protocol       = "tcp"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-${replace(each.key, "/", "-")}"
  })
}

# ── Egress rule ───────────────────────────────────────────────────────────────
# All egress allowed at the SG level — the cluster sits in a private spoke
# subnet whose only path out is the TGW, where the Hub firewall/NAT enforces
# the actual egress policy.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all egress. Effective egress policy is enforced at the Hub (TGW firewall/NAT)."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # all protocols

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-egress-all"
  })
}
