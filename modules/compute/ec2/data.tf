# modules/compute/ec2/data.tf
#
# VPC + subnet discovery — finds the Spoke VPC by Name convention and the
# target subnet by the Tier/AZ tag contract the VPC module stamps.
# NO VPC/subnet IDs passed in; NO shared state.
#
# Discovery contract (modules/networking/vpc):
#   VPC    : tag Name = vpc-aw-{region_short}-{service}-{ambiente}
#   Subnet : tag Tier = app|bdd|gwlb  +  tag AZ = a|b  (within that VPC)

data "aws_caller_identity" "current" {}

# The Spoke VPC that owns the target subnet (by Name convention).
data "aws_vpc" "spoke" {
  tags = {
    Name = local.vpc_name_to_discover
  }
}

# Target subnet — resolved by tier + AZ inside the discovered VPC.
data "aws_subnet" "target" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.spoke.id]
  }
  filter {
    name   = "tag:Tier"
    values = [var.subnet_tier]
  }
  filter {
    name   = "tag:AZ"
    values = [var.subnet_az]
  }
}

# AMI resolution — latest AMI from the SSM public parameter (only when no
# explicit ami_id is supplied).
data "aws_ssm_parameter" "ami" {
  count = var.ami_id == "" ? 1 : 0

  name = var.ami_ssm_parameter
}

# Guardrail: the workflow-provided account must match the active account, else
# the VPC/subnet lookups would silently target the wrong account.
resource "null_resource" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id}). Instance and discovered VPC must be in the SAME account."
    }
  }
}
