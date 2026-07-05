# modules/database/aurora-postgresql/data.tf
#
# VPC + subnet + KMS discovery — finds the Spoke VPC by Name convention, the
# BDD-tier subnets by the Tier/AZ tag contract the VPC module stamps, and the
# account's pre-existing RDS CMK by alias.
# NO VPC/subnet/key IDs passed in; NO shared state.
#
# Discovery contract (modules/networking/vpc):
#   VPC    : tag Name = vpc-aw-{region_short}-{service}-{ambiente}
#   Subnet : tag Tier = bdd  +  tag AZ = a|b  (within that VPC)
#
# KMS contract (account baseline):
#   The RDS CMK already exists in every account — resolved by alias
#   (var.kms_key_alias, default alias/rds). Pass kms_key_arn to override.

data "aws_caller_identity" "current" {}

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

# Guardrail: the workflow-provided account must match the active account, else
# the VPC/subnet/KMS lookups would silently target the wrong account.
resource "null_resource" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id}). Cluster and discovered VPC/KMS must be in the SAME account."
    }
  }
}
