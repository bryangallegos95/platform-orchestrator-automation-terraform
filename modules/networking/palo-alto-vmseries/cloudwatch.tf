# modules/networking/palo-alto-vmseries/cloudwatch.tf
#
# CloudWatch resources for PA VM-Series monitoring:
#   - Log groups for PA traffic/threat/system logs
#   - Alarms for ASG health and scaling decisions
#   - Dashboard (optional, for operational visibility)

# ── Log Groups ────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "traffic" {
  name              = "/paloalto/${var.name_prefix}/traffic"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-log-traffic"
  })
}

resource "aws_cloudwatch_log_group" "threat" {
  name              = "/paloalto/${var.name_prefix}/threat"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-log-threat"
  })
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/paloalto/${var.name_prefix}/system"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-log-system"
  })
}

# ── Alarms ────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "${var.name_prefix}-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/GatewayELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "One or more PA VM-Series targets are unhealthy"
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.gwlb.arn_suffix
    LoadBalancer = aws_lb.gwlb.arn_suffix
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-alarm-unhealthy"
  })
}
