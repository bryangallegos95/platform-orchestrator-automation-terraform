# modules/networking/centralized-endpoints/main.tf
#
# Centralized VPC Endpoints — deployed once in Egress VPC, shared by all spokes.
# Requires: Route 53 PHZ association with spoke VPCs for DNS resolution.

# ── Endpoint Subnets ───────────────────────────────────────────────────
resource "aws_subnet" "endpoint_a" {
  vpc_id               = var.vpc_id
  cidr_block           = var.endpoint_subnet_a_cidr
  availability_zone_id = var.az_id_a

  tags = merge(local.tags, {
    Name = "snet-aw-${local.region_short}-egress-private-vpce-1a"
    Tier = "vpce"
    AZ   = "a"
  })
}

resource "aws_subnet" "endpoint_b" {
  vpc_id               = var.vpc_id
  cidr_block           = var.endpoint_subnet_b_cidr
  availability_zone_id = var.az_id_b

  tags = merge(local.tags, {
    Name = "snet-aw-${local.region_short}-egress-private-vpce-1b"
    Tier = "vpce"
    AZ   = "b"
  })
}

# ── Route Table for Endpoint Subnets ──────────────────────────────────
resource "aws_route_table" "endpoint" {
  vpc_id = var.vpc_id

  tags = merge(local.tags, {
    Name = "rt-aw-${local.region_short}-egress-vpce"
  })
}

resource "aws_route" "endpoint_to_spokes" {
  route_table_id         = aws_route_table.endpoint.id
  destination_cidr_block = "172.27.0.0/16"
  transit_gateway_id     = var.tgw_id
}

resource "aws_route" "endpoint_to_onprem_10" {
  route_table_id         = aws_route_table.endpoint.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = var.tgw_id
}

resource "aws_route" "endpoint_to_onprem_172" {
  route_table_id         = aws_route_table.endpoint.id
  destination_cidr_block = "172.16.0.0/16"
  transit_gateway_id     = var.tgw_id
}

resource "aws_route_table_association" "endpoint_a" {
  subnet_id      = aws_subnet.endpoint_a.id
  route_table_id = aws_route_table.endpoint.id
}

resource "aws_route_table_association" "endpoint_b" {
  subnet_id      = aws_subnet.endpoint_b.id
  route_table_id = aws_route_table.endpoint.id
}

# ── Security Group ────────────────────────────────────────────────────
resource "aws_security_group" "vpce" {
  name        = "sgp-aw-${local.region_short}-vpce-centralized"
  description = "Allow HTTPS access to centralized VPC Endpoints from all spokes and on-prem"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      description = "HTTPS from ${ingress.value}"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "sgp-aw-${local.region_short}-vpce-centralized"
  })
}

# ── VPC Interface Endpoints ───────────────────────────────────────────
resource "aws_vpc_endpoint" "this" {
  for_each = toset(var.endpoints)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false # We use PHZ instead for cross-VPC resolution

  subnet_ids = [
    aws_subnet.endpoint_a.id,
    aws_subnet.endpoint_b.id,
  ]

  security_group_ids = [aws_security_group.vpce.id]

  tags = merge(local.tags, {
    Name = "vpce-aw-${local.region_short}-centralized-${each.key}"
  })
}
