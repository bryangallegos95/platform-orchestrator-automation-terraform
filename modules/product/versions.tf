# modules/product/versions.tf
#
# Terraform and provider constraints for the product compositor module.
# This module composes building blocks (aurora, sqs, elasticache, irsa) into
# a single state per environment. Each building block is called as a child
# module with its own provider constraints — this file sets the FLOOR.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}
