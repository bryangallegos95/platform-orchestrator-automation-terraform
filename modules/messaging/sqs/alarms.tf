# modules/messaging/sqs/alarms.tf
#
# CloudWatch Metric Alarms for SQS queues (WAF compliance baseline).
#
# Alarms created:
#   1. DLQ depth — ApproximateNumberOfMessagesVisible > threshold for 5 min.
#      Fires whenever ANY message lands in the DLQ, signalling consumer failures.
#   2. Main queue message age — ApproximateAgeOfOldestMessage > threshold.
#      Fires when messages sit unprocessed too long, signalling stuck consumers.
#
# Both alarms are optional (controlled by thresholds) and push to an
# SNS topic ARN if provided.

# ── DLQ Depth Alarm ───────────────────────────────────────────────────────────
# Triggers when messages appear in the DLQ (threshold default = 0, i.e. any
# message in DLQ is abnormal and warrants alerting).
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  for_each = local.queues

  alarm_name        = "sqs-dlq-depth-${each.value.dlq_name}"
  alarm_description = "DLQ ${each.value.dlq_name} has messages visible above threshold for 5 minutes"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = each.value.dlq_name
  }

  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_dlq_threshold
  treat_missing_data  = "notBreaching"

  actions_enabled = length(var.alarm_actions) > 0
  alarm_actions   = var.alarm_actions
  ok_actions      = var.alarm_actions

  tags = merge(local.tags, {
    Name      = "sqs-dlq-depth-${each.key}"
    AlarmType = "DLQ-Depth"
  })

  depends_on = [aws_sqs_queue.dlq]
}

# ── Main Queue Message Age Alarm ──────────────────────────────────────────────
# Triggers when the oldest message in the main queue exceeds the age threshold,
# indicating consumers are not keeping up or are stuck.
resource "aws_cloudwatch_metric_alarm" "queue_age" {
  for_each = local.queues

  alarm_name        = "sqs-age-${each.value.queue_name}"
  alarm_description = "Queue ${each.value.queue_name} oldest message age exceeds ${var.alarm_age_threshold_seconds}s"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateAgeOfOldestMessage"
  dimensions = {
    QueueName = each.value.queue_name
  }

  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_age_threshold_seconds
  treat_missing_data  = "notBreaching"

  actions_enabled = length(var.alarm_actions) > 0
  alarm_actions   = var.alarm_actions
  ok_actions      = var.alarm_actions

  tags = merge(local.tags, {
    Name      = "sqs-age-${each.key}"
    AlarmType = "Message-Age"
  })

  depends_on = [aws_sqs_queue.main]
}
