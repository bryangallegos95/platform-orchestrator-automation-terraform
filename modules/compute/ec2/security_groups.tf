# modules/compute/ec2/security_groups.tf
#
# Dedicated Security Group for the instance.
#
# Default posture: NO inbound rules. Access is via SSM Session Manager, which
# needs no inbound ports — traffic reaches the centralized SSM VPC endpoints
# (Egress VPC / modules/networking/centralized-endpoints) over the TGW.
# Inbound rules are opt-in via var.ingress_rules.
#
# Uses the modern aws_vpc_security_group_ingress_rule / _egress_rule resources
# (AWS provider >= 5.x) rather than inline blocks, which enables independent
# lifecycle management of each rule.

resource "aws_security_group" "this" {
  name        = local.sg_name
  description = "SG for ${local.instance_name}. Default: no inbound (SSM-only access). Managed by Terraform (compute/ec2 module)."
  vpc_id      = data.aws_vpc.spoke.id

  tags = merge(local.tags, { Name = local.sg_name })
}

# ── Ingress rules — one per entry in var.ingress_rules ────────────────────────
resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = {
    for r in var.ingress_rules :
    "${r.cidr}-${r.protocol}-${r.from_port}-${r.to_port}" => r
  }

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol

  tags = merge(local.tags, {
    Name = "sgr-aw-${local.region_short}-${var.service}-${var.workload}-${replace(each.key, "/", "-")}"
  })
}

# ── Egress rule ───────────────────────────────────────────────────────────────
# All egress allowed at the SG level — the instance sits in a private spoke
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
