# modules/compute/ec2/main.tf
#
# Single EC2 instance in an existing Spoke VPC (Hub-and-Spoke topology).
# One module call = one instance. Call the module once per instance
# (e.g. 'bastion', 'sftp', 'app01' via var.workload).
#
# What this module creates:
#   1. EC2 instance in a discovered private subnet (tier + AZ selectable)
#   2. Dedicated Security Group (no inbound by default — SSM-only access)
#   3. IAM role + instance profile with AmazonSSMManagedInstanceCore
#
# What this module does NOT create (lives elsewhere):
#   - VPC / subnets / routing        → modules/networking/vpc
#   - VPC endpoints for SSM          → modules/networking/centralized-endpoints
#   - KMS keys                       → account baseline (pass ebs_kms_key_arn)
#
# Hardening baked in (not configurable off):
#   - IMDSv2 required by default (var.ec2_metadata_http_tokens)
#   - Root EBS volume always encrypted
#   - No public IP (spoke subnets are private; no IGW exists anyway)
#   - EBS-optimized
#   - Termination protection auto-enabled in preprod/prod/dr

resource "aws_instance" "this" {
  ami           = local.ami_id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.target.id

  vpc_security_group_ids = concat(
    [aws_security_group.this.id],
    var.additional_security_group_ids
  )

  iam_instance_profile = aws_iam_instance_profile.this.name

  key_name  = var.key_name
  user_data = var.user_data

  # Private spoke — never expose a public IP.
  associate_public_ip_address = false

  ebs_optimized           = true
  monitoring              = var.enable_detailed_monitoring
  disable_api_termination = local.termination_protection

  # ── IMDSv2 (bank standard: required) ─────────────────────────────────────
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.ec2_metadata_http_tokens
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # ── Root volume — always encrypted ───────────────────────────────────────
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn != "" ? var.ebs_kms_key_arn : null
    delete_on_termination = true

    tags = merge(local.tags, { Name = local.root_volume_name })
  }

  tags = merge(local.tags, { Name = local.instance_name })

  lifecycle {
    # When the AMI is resolved from the SSM 'latest' parameter, every new AMI
    # release would otherwise force instance replacement on the next plan.
    # Pin the AMI at creation time; upgrades are deliberate (set ami_id or
    # taint/replace the instance explicitly).
    ignore_changes = [ami]
  }
}
