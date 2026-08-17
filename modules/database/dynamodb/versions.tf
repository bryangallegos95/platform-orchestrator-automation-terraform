# modules/database/dynamodb/versions.tf
#
# Terraform and AWS provider version constraints.
# Pinned to the same range as the rest of the module library (aurora-postgresql,
# elasticache-serverless, sqs) so a son repo can consume several blocks in one
# state without a provider conflict.
#
# NOTE: the reference implementation (POC, CL-LLD-DAT-01 §10.1) was validated
# with AWS provider 6.x, where global_secondary_index accepts key_schema blocks.
# Under the 5.x range this library pins, a GSI declares hash_key / range_key
# directly — that is the syntax used in main.tf.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
    # terraform_data (built-in, Terraform >= 1.4) backs guards.tf — no external
    # provider needed.
  }
}
