# modules/networking/palo-alto-vmseries/iam.tf
#
# IAM Role and Instance Profile for PA VM-Series instances.
# Permissions: S3 bootstrap read, CloudWatch metrics/logs, SSM for management.

resource "aws_iam_role" "vmseries" {
  name_prefix = "${var.name_prefix}-vm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vm-role"
  })
}

resource "aws_iam_instance_profile" "vmseries" {
  name_prefix = "${var.name_prefix}-vm-"
  role        = aws_iam_role.vmseries.name

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vm-profile"
  })
}

# ── S3 Bootstrap Read Access ──────────────────────────────────────────────────

resource "aws_iam_role_policy" "bootstrap_s3" {
  name_prefix = "bootstrap-s3-"
  role        = aws_iam_role.vmseries.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = var.create_bootstrap_bucket ? [
          aws_s3_bucket.bootstrap[0].arn,
          "${aws_s3_bucket.bootstrap[0].arn}/*"
        ] : [
          "arn:aws:s3:::${var.bootstrap_bucket_name}",
          "arn:aws:s3:::${var.bootstrap_bucket_name}/*"
        ]
      }
    ]
  })
}

# ── CloudWatch Metrics and Logs ───────────────────────────────────────────────

resource "aws_iam_role_policy" "cloudwatch" {
  name_prefix = "cloudwatch-"
  role        = aws_iam_role.vmseries.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = var.scaling_config.cloudwatch_namespace
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/paloalto/*"
      }
    ]
  })
}

# ── SSM for Session Manager (no SSH bastion needed) ───────────────────────────

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.vmseries.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
