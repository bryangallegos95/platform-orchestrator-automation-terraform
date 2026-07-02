# modules/openshift/rosa-hcp/data.tf
#
# Subnet discovery (Option 3) — finds the VPC + private app subnets by the tag
# contract the VPC module stamps. NO subnet IDs passed in; NO shared state.
#
# Discovery triplet: rosa=true + env=<ambiente> + dominio=<discovery_dominio>
# (defaults to var.dominio; override via vpc_discovery_dominio when the VPC
# naming service differs from the cluster dominio).
# AZ resolution uses the VPC module's per-subnet AZ tag (AZ=a / AZ=b).

data "aws_caller_identity" "current" {}

# The VPC that owns the ROSA subnets (by Name convention).
data "aws_vpc" "rosa" {
  tags = {
    Name = local.vpc_name_to_discover
  }
}

# All ROSA-eligible subnets in that VPC (sanity / output).
data "aws_subnets" "rosa" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.rosa.id]
  }
  filter {
    name   = "tag:${var.rosa_subnet_discovery_tag}"
    values = ["true"]
  }
  filter {
    name   = "tag:bancointernacional.ec/env"
    values = [var.ambiente]
  }
  filter {
    name   = "tag:bancointernacional.ec/dominio"
    values = [local.discovery_dominio]
  }
}

# AZ-a subnet.
data "aws_subnet" "rosa_a" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.rosa.id]
  }
  filter {
    name   = "tag:${var.rosa_subnet_discovery_tag}"
    values = ["true"]
  }
  filter {
    name   = "tag:AZ"
    values = ["a"]
  }
  filter {
    name   = "tag:bancointernacional.ec/env"
    values = [var.ambiente]
  }
  filter {
    name   = "tag:bancointernacional.ec/dominio"
    values = [local.discovery_dominio]
  }
}

# AZ-b subnet (resolved always — VPC has both app subnets tagged; used by 2-pool envs).
data "aws_subnet" "rosa_b" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.rosa.id]
  }
  filter {
    name   = "tag:${var.rosa_subnet_discovery_tag}"
    values = ["true"]
  }
  filter {
    name   = "tag:AZ"
    values = ["b"]
  }
  filter {
    name   = "tag:bancointernacional.ec/env"
    values = [var.ambiente]
  }
  filter {
    name   = "tag:bancointernacional.ec/dominio"
    values = [local.discovery_dominio]
  }
}

# Guardrail: the workflow-provided account must match the active account, else the
# subnet lookups would silently target the wrong account.
resource "null_resource" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id}). Cluster and tagged subnets must be in the SAME account."
    }
  }
}
