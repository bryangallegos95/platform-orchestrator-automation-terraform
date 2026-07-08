# modules/networking/palo-alto-vmseries/asg.tf
#
# Auto Scaling Group + Launch Template for PA VM-Series.
# In PROD: min=2, desired=2, max=4 (active instances).
# In DR:   min=0, desired=0, max=4 + Warm Pool (2 stopped).

# ── Launch Template ───────────────────────────────────────────────────────────

resource "aws_launch_template" "vmseries" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null

  # eth0 = data-plane (after mgmt-interface-swap)
  network_interfaces {
    device_index                = 0
    security_groups             = [aws_security_group.data_plane.id]
    delete_on_termination       = true
    associate_public_ip_address = false
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.vmseries.arn
  }

  user_data = base64encode(local.bootstrap_user_data)

  # IMDSv2 required
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # Encrypted root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 60
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.name_prefix}-vm"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}


# ── Auto Scaling Group ────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "vmseries" {
  name_prefix      = "${var.name_prefix}-asg-"
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  vpc_zone_identifier = var.data_subnet_ids
  target_group_arns   = [aws_lb_target_group.gwlb.arn]

  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.vmseries.id
    version = "$Latest"
  }

  # Spread instances across AZs
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = var.health_check_grace_period
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-vm"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity] # Allow manual scaling / DR failover
  }
}


# ── Warm Pool (DR mode — pre-bootstrapped stopped instances) ──────────────────

resource "aws_autoscaling_group_warm_pool" "vmseries" {
  count = var.warm_pool_config.enabled ? 1 : 0

  autoscaling_group_name     = aws_autoscaling_group.vmseries.name
  pool_state                 = var.warm_pool_config.pool_state
  min_size                   = var.warm_pool_config.min_size
  max_group_prepared_capacity = var.warm_pool_config.max_group_prepared_capacity

  instance_reuse_policy {
    reuse_on_scale_in = var.warm_pool_config.reuse_on_scale_in
  }
}

# ── Lifecycle Hook (for Lambda to attach mgmt ENI) ────────────────────────────

resource "aws_autoscaling_lifecycle_hook" "launch" {
  name                   = "${var.name_prefix}-launch-hook"
  autoscaling_group_name = aws_autoscaling_group.vmseries.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  heartbeat_timeout      = 600
  default_result         = "ABANDON"
}

resource "aws_autoscaling_lifecycle_hook" "terminate" {
  name                   = "${var.name_prefix}-terminate-hook"
  autoscaling_group_name = aws_autoscaling_group.vmseries.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  heartbeat_timeout      = 300
  default_result         = "CONTINUE"
}
