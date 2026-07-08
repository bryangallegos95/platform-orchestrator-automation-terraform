# modules/networking/palo-alto-vmseries/security_groups.tf
#
# Security Groups for PA VM-Series:
#   - Data-plane SG: Allows GENEVE (UDP 6081) from GWLB + health checks
#   - Management SG: Allows outbound HTTPS (SCM, licensing) + inbound SSH (emergency)

# ══════════════════════════════════════════════════════════════════════════════
# Data-plane Security Group (eth0 after mgmt-interface-swap)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_security_group" "data_plane" {
  name_prefix = "${var.name_prefix}-data-"
  description = "PA VM-Series data-plane: GENEVE from GWLB + health checks"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sg-data"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# GENEVE encapsulation from GWLB (UDP 6081)
resource "aws_security_group_rule" "data_geneve_in" {
  type              = "ingress"
  from_port         = 6081
  to_port           = 6081
  protocol          = "udp"
  cidr_blocks       = [var.data_plane_cidr]
  security_group_id = aws_security_group.data_plane.id
  description       = "GENEVE from GWLB"
}

# Health checks from GWLB (HTTPS 443)
resource "aws_security_group_rule" "data_health_check_in" {
  type              = "ingress"
  from_port         = var.gwlb_health_check.port
  to_port           = var.gwlb_health_check.port
  protocol          = "tcp"
  cidr_blocks       = [var.data_plane_cidr]
  security_group_id = aws_security_group.data_plane.id
  description       = "GWLB health checks"
}

# All outbound (GENEVE responses to GWLB)
resource "aws_security_group_rule" "data_all_out" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.data_plane.id
  description       = "All outbound (GENEVE return to GWLB)"
}

# ══════════════════════════════════════════════════════════════════════════════
# Management Security Group (eth1 after mgmt-interface-swap)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_security_group" "mgmt" {
  name_prefix = "${var.name_prefix}-mgmt-"
  description = "PA VM-Series management: SCM, licensing, content updates"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sg-mgmt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS outbound (Strata Cloud Manager, licensing servers, content updates)
resource "aws_security_group_rule" "mgmt_https_out" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mgmt.id
  description       = "HTTPS to SCM, licensing, updates"
}

# Device registration port (TCP 3978) to SCM
resource "aws_security_group_rule" "mgmt_device_reg_out" {
  type              = "egress"
  from_port         = 3978
  to_port           = 3978
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mgmt.id
  description       = "Device registration to SCM (TCP 3978)"
}

# DNS outbound (UDP 53 — AWS VPC DNS)
resource "aws_security_group_rule" "mgmt_dns_out" {
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mgmt.id
  description       = "DNS resolution"
}

# NTP outbound (UDP 123)
resource "aws_security_group_rule" "mgmt_ntp_out" {
  type              = "egress"
  from_port         = 123
  to_port           = 123
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mgmt.id
  description       = "NTP time sync"
}

# SSH inbound (emergency access — restricted to internal CIDRs)
resource "aws_security_group_rule" "mgmt_ssh_in" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.mgmt_allowed_cidrs
  security_group_id = aws_security_group.mgmt.id
  description       = "SSH emergency access (internal only)"
}

# HTTPS inbound (Panorama/SCM push, GWLB health checks routed via mgmt)
resource "aws_security_group_rule" "mgmt_https_in" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.mgmt_allowed_cidrs
  security_group_id = aws_security_group.mgmt.id
  description       = "HTTPS inbound (SCM push, health checks)"
}
