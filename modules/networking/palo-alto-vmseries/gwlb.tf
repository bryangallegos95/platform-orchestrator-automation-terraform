# modules/networking/palo-alto-vmseries/gwlb.tf
#
# Gateway Load Balancer — receives GENEVE-encapsulated traffic and distributes
# it across the PA VM-Series ASG instances (data-plane ENIs).
#
# The GWLB itself lives in the existing FW subnets (data_subnet_ids).
# It uses cross-zone load balancing to ensure even distribution.

resource "aws_lb" "gwlb" {
  name               = "${var.name_prefix}-gwlb"
  load_balancer_type = "gateway"
  subnets            = var.data_subnet_ids

  enable_cross_zone_load_balancing = var.cross_zone_load_balancing

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-gwlb"
  })
}

# ── Target Group ──────────────────────────────────────────────────────────────
# Targets are registered automatically by the ASG.
# Health checks hit the PA management profile (HTTPS:443 on data-plane interface).

resource "aws_lb_target_group" "gwlb" {
  name                 = "${var.name_prefix}-tg"
  port                 = 6081
  protocol             = "GENEVE"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    port                = var.gwlb_health_check.port
    protocol            = var.gwlb_health_check.protocol
    healthy_threshold   = var.gwlb_health_check.healthy_threshold
    unhealthy_threshold = var.gwlb_health_check.unhealthy_threshold
    interval            = var.gwlb_health_check.interval
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-tg"
  })
}

# ── Listener ──────────────────────────────────────────────────────────────────

resource "aws_lb_listener" "gwlb" {
  load_balancer_arn = aws_lb.gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gwlb.arn
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-listener"
  })
}
