# modules/database/elasticache-serverless/data.tf
#
# VPC, subnet, and KMS key discovery. Same contract as aurora-postgresql/data.tf.
# No IDs are passed in — everything is discovered by the tag/naming contract
# established by modules/networking/vpc.
# VPC discovery uses local.vpc_service (resolved from vpc_discovery_service or workload).

# ── Current identity ──────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── VPC discovery (by Name tag — contract with networking/vpc module) ─────────
data "aws_vpc" "spoke" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name_to_discover]
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
