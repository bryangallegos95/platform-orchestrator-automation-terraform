# modules/networking/vpc/main.tf
#
# Spoke VPC — Hub-and-Spoke topology.
#
# What this module creates:
#   1. VPC
#   2. 6 private subnets (app-a/b, bdd-a/b, gwlb-a/b)
#   3. TGW attachment → Hub TGW (app subnets are the attachment subnets)
#   4. Optional explicit TGW RT association + propagation
#   5. 2 private route tables (one per AZ, shared by all tiers in that AZ)
#   6. Default route 0.0.0.0/0 → TGW on both route tables
#   7. Route table associations (all 6 subnets)
#   8. VPC Flow Logs → CloudWatch
#
# What this module does NOT create (lives in Hub account / separate module):
#   - IGW, NAT GW, Elastic IPs
#   - Transit Gateway itself
#   - Hub VPC, Hub route tables
#   - VPC Endpoints (S3, SSM, EC2, etc.) — created ONCE in the Egress VPC via
#     modules/networking/centralized-endpoints; spokes resolve them through
#     Route 53 Private Hosted Zone associations (not per-spoke endpoints)

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.tags, { Name = local.vpc_name })
}

# ── Subnets — App tier ────────────────────────────────────────────────────────
resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_app_a_cidr
  availability_zone_id = local.az_id_a

  tags = merge(local.tags, {
    Name = local.snet_app_a
    Tier = "app"
    AZ   = "a"
  }, local.rosa_subnet_tags)
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_app_b_cidr
  availability_zone_id = local.az_id_b

  tags = merge(local.tags, {
    Name = local.snet_app_b
    Tier = "app"
    AZ   = "b"
  }, local.rosa_subnet_tags)
}

# ── Subnets — BDD (database) tier ─────────────────────────────────��──────────
resource "aws_subnet" "bdd_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_bdd_a_cidr
  availability_zone_id = local.az_id_a

  tags = merge(local.tags, {
    Name = local.snet_bdd_a
    Tier = "bdd"
    AZ   = "a"
  })
}

resource "aws_subnet" "bdd_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_bdd_b_cidr
  availability_zone_id = local.az_id_b

  tags = merge(local.tags, {
    Name = local.snet_bdd_b
    Tier = "bdd"
    AZ   = "b"
  })
}

# ── Subnets — GWLB / API-GW endpoint tier ────────────────────────────────────
resource "aws_subnet" "gwlb_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_gwlb_a_cidr
  availability_zone_id = local.az_id_a

  tags = merge(local.tags, {
    Name = local.snet_gwlb_a
    Tier = "gwlb"
    AZ   = "a"
  })
}

resource "aws_subnet" "gwlb_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_gwlb_b_cidr
  availability_zone_id = local.az_id_b

  tags = merge(local.tags, {
    Name = local.snet_gwlb_b
    Tier = "gwlb"
    AZ   = "b"
  })
}

# ── Transit Gateway VPC Attachment ────────────────────────────────────────────
# The App subnets (one per AZ) are the designated TGW attachment subnets.
# This is the only path out of the spoke — all traffic goes through the Hub.
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.tgw_id
  vpc_id             = aws_vpc.this.id

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id,
  ]

  dns_support  = "disable"
  ipv6_support = "disable"

  transit_gateway_default_route_table_association = (var.tgw_route_table_id == null && var.tgw_manage_route_table) ? true : false
  transit_gateway_default_route_table_propagation = (var.tgw_route_table_id == null && var.tgw_manage_route_table) ? true : false

  tags = merge(local.tags, { Name = local.tgw_attachment_name })

  # Force full replacement when subnets are recreated (AZ change, CIDR change)
  # Without this, Terraform tries to modify in-place → IncorrectState error
  lifecycle {
    replace_triggered_by = [
      aws_subnet.app_a.id,
      aws_subnet.app_b.id,
    ]
  }
}

# ── Optional: explicit TGW Route Table association ────────────────────────────
# Only created when tgw_route_table_id is supplied by the caller.
# This lets the Hub team control which TGW RT each spoke propagates into
# without touching this module.
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  count = (var.tgw_route_table_id != null && var.tgw_manage_route_table) ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  count = (var.tgw_route_table_id != null && var.tgw_manage_route_table) ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.tgw_route_table_id
}

# ── Route Tables — one per AZ ─────────────────────────────────────────────────
# All three subnet tiers in the same AZ share the same route table.
# AZ-A RT
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = local.rt_private_a })
}

# AZ-B RT
resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = local.rt_private_b })
}

# ── Default route 0.0.0.0/0 → TGW ────────────────────────────────────────────
# All egress leaves the spoke through the Transit Gateway to the Hub,
# where the Hub's NAT GW / Firewall handles internet-bound traffic.
resource "aws_route" "default_a" {
  route_table_id         = aws_route_table.private_a.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id

  # The route can only be created after the TGW attachment is active.
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route" "default_b" {
  route_table_id         = aws_route_table.private_b.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# ── Route Table Associations ──────────────────────────────────────────────────
# App tier
resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.private_b.id
}

# BDD tier
resource "aws_route_table_association" "bdd_a" {
  subnet_id      = aws_subnet.bdd_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "bdd_b" {
  subnet_id      = aws_subnet.bdd_b.id
  route_table_id = aws_route_table.private_b.id
}

# GWLB tier
resource "aws_route_table_association" "gwlb_a" {
  subnet_id      = aws_subnet.gwlb_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "gwlb_b" {
  subnet_id      = aws_subnet.gwlb_b.id
  route_table_id = aws_route_table.private_b.id
}

# ── VPC Flow Logs → CloudWatch ────────────────────────────────────────────────

# CloudWatch Log Group
# Encrypted with KMS CMK (CIS AWS 2.0 / Prowler AWS-0017)
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = local.flow_log_group
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_arn

  tags = merge(local.tags, { Name = local.flow_log_group })
}

# IAM Role — allows VPC Flow Logs service to write to CloudWatch
resource "aws_iam_role" "flow_logs" {
  name = local.flow_log_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "vpc-flow-logs-cw-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

# Flow Log resource
resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = var.flow_log_traffic_type
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = merge(local.tags, { Name = local.flow_log_name })
}
# ── Data sources ──────────────────────────────────────────────────────────────
# Used to scope the IAM assume-role condition to the target account.
data "aws_caller_identity" "current" {}
