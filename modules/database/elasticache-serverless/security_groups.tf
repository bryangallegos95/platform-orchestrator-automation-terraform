# modules/database/elasticache-serverless/security_groups.tf
#
# Dedicated Security Group for the ElastiCache Serverless VPC endpoints.
#
# Default posture: NO inbound rules. Consumers are granted access explicitly via:
#   - var.allowed_security_group_ids → SG-to-SG rules (preferred: identity-based)
#   - var.allowed_cidrs              → CIDR rules (e.g. app-tier subnets)
#
# LOCKED: Both ports (6379 primary + 6380 reader) are opened for each consumer.
# ElastiCache Serverless requires both ports accessible — many client libraries
# connect to both even if Read From Replica is not actively used.
#
# Uses modern aws_vpc_security_group_ingress_rule / _egress_rule resources
# (AWS provider >= 5.x) — same pattern as aurora-postgresql/security_groups.tf.

resource "aws_security_group" "this" {
  name        = local.sg_name
  description = "SG for ${local.cache_name}. Default: no inbound. Cache ports opt-in per consumer. Managed by Terraform."
  vpc_id      = data.aws_vpc.spoke.id

  lifecycle {
    ignore_changes = [description]
  }

  tags = merge(local.tags, { Name = local.sg_name })
}

# ── Ingress — SG-to-SG: Primary port (6379) ─────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "from_sg_primary" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "ElastiCache primary (${local.cache_port_primary}) from consumer SG ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = local.cache_port_primary
  to_port                      = local.cache_port_primary
  ip_protocol                  = "tcp"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-ec-${each.value}-primary"
  })
}

# ── Ingress — SG-to-SG: Reader port (6380) ──────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "from_sg_reader" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "ElastiCache reader (${local.cache_port_reader}) from consumer SG ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = local.cache_port_reader
  to_port                      = local.cache_port_reader
  ip_protocol                  = "tcp"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-ec-${each.value}-reader"
  })
}

# ── Ingress — CIDR: Primary port (6379) ──────────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "from_cidr_primary" {
  for_each = { for r in var.allowed_cidrs : r.cidr => r }

  security_group_id = aws_security_group.this.id
  description       = "${each.value.description} - primary (${local.cache_port_primary})"
  cidr_ipv4         = each.value.cidr
  from_port         = local.cache_port_primary
  to_port           = local.cache_port_primary
  ip_protocol       = "tcp"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-ec-${replace(each.key, "/", "-")}-primary"
  })
}

# ── Ingress — CIDR: Reader port (6380) ───────────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "from_cidr_reader" {
  for_each = { for r in var.allowed_cidrs : r.cidr => r }

  security_group_id = aws_security_group.this.id
  description       = "${each.value.description} - reader (${local.cache_port_reader})"
  cidr_ipv4         = each.value.cidr
  from_port         = local.cache_port_reader
  to_port           = local.cache_port_reader
  ip_protocol       = "tcp"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-ec-${replace(each.key, "/", "-")}-reader"
  })
}

# ── Egress — all allowed (Hub TGW firewall enforces policy) ───────────────────
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all egress. Effective egress policy enforced at Hub (TGW firewall/NAT)."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-ec-egress-all"
  })
}
