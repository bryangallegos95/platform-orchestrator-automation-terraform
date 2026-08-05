# modules/database/elasticache-serverless/data.tf
#
# VPC, subnet, and KMS key discovery. Same contract as aurora-postgresql/data.tf.
# No IDs are passed in — everything is discovered by the tag contract
# established by modules/networking/vpc.
# VPC discovery uses tag 'ou' = var.service (OU name, lowercase).

# ── Current identity ──────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── VPC discovery (by OU tag — decoupled from VPC naming convention) ──────────
data "aws_vpc" "spoke" {
  tags = {
    ou = local.vpc_ou
  }
}

# ── Subnet discovery (cache tier — uses same BDD-tier subnets as Aurora) ──────
# ElastiCache Serverless creates VPC endpoints in these subnets.
data "aws_subnet" "cache_a" {
  vpc_id = data.aws_vpc.spoke.id

  filter {
    name   = "tag:Tier"
    values = ["bdd"]
  }

  filter {
    name   = "tag:AZ"
    values = ["a"]
  }
}

data "aws_subnet" "cache_b" {
  vpc_id = data.aws_vpc.spoke.id

  filter {
    name   = "tag:Tier"
    values = ["bdd"]
  }

  filter {
    name   = "tag:AZ"
    values = ["b"]
  }
}

# ── KMS key discovery ─────────────────────────────────────────────────────────
data "aws_kms_alias" "elasticache" {
  count = var.kms_key_arn == "" ? 1 : 0
  name  = var.kms_key_alias
}

# Pre-existing account CloudWatch Logs CMK — encrypts the managed log groups
# (see logs.tf). Resolved by alias unless an explicit ARN is supplied.
data "aws_kms_alias" "cwlogs" {
  count = var.cloudwatch_logs_kms_key_arn == "" ? 1 : 0
  name  = var.cloudwatch_logs_kms_key_alias
}
