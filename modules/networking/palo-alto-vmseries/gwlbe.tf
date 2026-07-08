# modules/networking/palo-alto-vmseries/gwlbe.tf
#
# GWLB Endpoints — VPC Endpoints of type GatewayLoadBalancer.
# These sit in the dedicated gwlbe-pa subnets (created by subnets.tf) and
# receive traffic routed from TGW subnets for inspection.
#
# Architecture:
#   TGW Subnet RT (0/0 → gwlbe-pa) → GWLBe → GWLB → PA data-plane
#   PA inspects → returns to GWLB → GWLBe → GWLBe Subnet RT (0/0 → TGW)

# ── VPC Endpoint Service (exposes the GWLB) ──────────────────────────────────

resource "aws_vpc_endpoint_service" "gwlb" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpce-svc"
  })
}

# ── GWLB Endpoints (one per AZ) ──────────────────────────────────────────────

resource "aws_vpc_endpoint" "gwlbe" {
  count = length(aws_subnet.gwlbe)

  vpc_id            = var.vpc_id
  service_name      = aws_vpc_endpoint_service.gwlb.service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.gwlbe[count.index].id]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-gwlbe-${count.index == 0 ? "1a" : "1b"}"
    AZ   = var.gwlbe_subnet_cidrs[count.index].az
  })
}
