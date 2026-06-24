# modules/openshift/rosa-hcp/iam.tf
#
# PER-CLUSTER IAM: OIDC config/provider + operator roles. Unique to this cluster,
# created/destroyed with it. References the SHARED account roles by prefix.

module "oidc_config_and_provider" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/oidc-config-and-provider"
  version = "~> 1.6.2"

  managed = true
  tags    = local.tags
}

module "operator_roles" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/operator-roles"
  version = "~> 1.6.2"

  operator_role_prefix = var.cluster_name
  oidc_endpoint_url    = module.oidc_config_and_provider.oidc_endpoint_url

  tags = local.tags
}
