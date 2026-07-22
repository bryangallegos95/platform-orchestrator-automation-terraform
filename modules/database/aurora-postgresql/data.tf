# modules/database/aurora-postgresql/data.tf
#
# VPC + subnet + KMS discovery — finds the Spoke VPC by Name convention, the
# BDD-tier subnets by the Tier/AZ tag contract the VPC module stamps, and the
# account's pre-existing CMKs by alias (RDS storage + CloudWatch Logs).
# NO VPC/subnet/key IDs passed in; NO shared state.
#
# Discovery contract (modules/networking/vpc):
#   VPC    : tag Name = vpc-aw-{region_short}-{service}-{ambiente}
#   Subnet : tag Tier = bdd  +  tag AZ = a|b  (within that VPC)
#
# KMS contract (account baseline — the module NEVER creates keys):
#   RDS storage / Performance Insights : alias/RDS    (var.kms_key_alias)
#   CloudWatch Logs (postgresql export): alias/CWLogs  (var.cloudwatch_logs_kms_key_alias)
#   Pass the matching *_kms_key_arn override to bypass alias discovery.

data "aws_caller_identity" "current" {}

# Active region — cross-checked against var.aws_region by the guards
# (terraform_data.guards) to catch a provider/region mismatch.
data "aws_region" "current" {}

# The Spoke VPC that owns the BDD subnets (by Name convention).
data "aws_vpc" "spoke" {
  tags = {
    Name = local.vpc_name_to_discover
  }
}

# BDD subnet — AZ a (always resolved; the subnet group spans both AZs so a
# multi-AZ upgrade never requires a subnet-group change).
data "aws_subnet" "bdd_a" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.spoke.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["bdd"]
  }
  filter {
    name   = "tag:AZ"
    values = ["a"]
  }
}

# BDD subnet — AZ b.
data "aws_subnet" "bdd_b" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.spoke.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["bdd"]
  }
  filter {
    name   = "tag:AZ"
    values = ["b"]
  }
}

# Pre-existing account RDS CMK — resolved by alias unless an explicit ARN is
# supplied. The module NEVER creates or manages KMS keys (account baseline).
data "aws_kms_alias" "rds" {
  count = var.kms_key_arn == "" ? 1 : 0

  name = var.kms_key_alias
}

# Pre-existing account CloudWatch Logs CMK — encrypts the managed PostgreSQL
# log group (see logs.tf). Resolved by alias unless an explicit ARN is supplied.
data "aws_kms_alias" "cwlogs" {
  count = var.cloudwatch_logs_kms_key_arn == "" ? 1 : 0

  name = var.cloudwatch_logs_kms_key_alias
}
