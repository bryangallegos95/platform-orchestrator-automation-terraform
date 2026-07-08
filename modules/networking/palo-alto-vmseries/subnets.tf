# modules/networking/palo-alto-vmseries/subnets.tf
#
# New subnets created by this module within the existing Inspection VPC:
#   - GWLBe subnets (GWLB Endpoints — return path to TGW)
#   - Management subnets (PA eth1 — SCM/licensing/updates access)
#
# The data-plane subnets (FW subnets) are EXISTING and passed via var.data_subnet_ids.
# They are NOT created here — they are shared with the existing AWS Network Firewall.

# ══════════════════════════════════════════════════════════════════════════════
# GWLB Endpoint Subnets (dedicated for Palo Alto GWLB Endpoints)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_subnet" "gwlbe" {
  count = length(var.gwlbe_subnet_cidrs)

  vpc_id               = var.vpc_id
  cidr_block           = var.gwlbe_subnet_cidrs[count.index].cidr
  availability_zone_id = var.gwlbe_subnet_cidrs[count.index].az

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-gwlbe-pa-${count.index == 0 ? "1a" : "1b"}"
    Tier = "gwlbe-paloalto"
  })
}

resource "aws_route_table" "gwlbe" {
  count = length(var.gwlbe_subnet_cidrs)

  vpc_id = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "rt-${var.name_prefix}-gwlbe-pa-${count.index == 0 ? "1a" : "1b"}"
  })
}

resource "aws_route_table_association" "gwlbe" {
  count = length(var.gwlbe_subnet_cidrs)

  subnet_id      = aws_subnet.gwlbe[count.index].id
  route_table_id = aws_route_table.gwlbe[count.index].id
}

# Return path: inspected traffic goes back to TGW for final routing
resource "aws_route" "gwlbe_to_tgw" {
  count = length(var.gwlbe_subnet_cidrs)

  route_table_id         = aws_route_table.gwlbe[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id
}

# ══════════════════════════════════════════════════════════════════════════════
# Management Subnets (PA eth1 — mgmt-interface-swap makes this eth1)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_subnet" "mgmt" {
  count = length(var.mgmt_subnet_cidrs)

  vpc_id               = var.vpc_id
  cidr_block           = var.mgmt_subnet_cidrs[count.index].cidr
  availability_zone_id = var.mgmt_subnet_cidrs[count.index].az

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-mgmt-pa-${count.index == 0 ? "1a" : "1b"}"
    Tier = "mgmt-paloalto"
  })
}

resource "aws_route_table" "mgmt" {
  count = length(var.mgmt_subnet_cidrs)

  vpc_id = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "rt-${var.name_prefix}-mgmt-pa-${count.index == 0 ? "1a" : "1b"}"
  })
}

resource "aws_route_table_association" "mgmt" {
  count = length(var.mgmt_subnet_cidrs)

  subnet_id      = aws_subnet.mgmt[count.index].id
  route_table_id = aws_route_table.mgmt[count.index].id
}

# Mgmt traffic exits via TGW → Egress VPC → NAT → Internet (for SCM, licensing)
resource "aws_route" "mgmt_to_tgw" {
  count = length(var.mgmt_subnet_cidrs)

  route_table_id         = aws_route_table.mgmt[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id
}
