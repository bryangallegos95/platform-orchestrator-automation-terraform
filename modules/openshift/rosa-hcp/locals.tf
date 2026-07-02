# modules/openshift/rosa-hcp/locals.tf
#
# Naming + tag factory — mirrors the VPC module convention.
#   region_short: ue1 (us-east-1) | ue2 (us-east-2)
#   VPC name to discover: vpc-aw-{region_short}-{dominio}-{ambiente}

locals {
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # Discovery may use a different dominio than the cluster (e.g. negocio clusters
  # on contenerizacion-named VPCs). Cluster tags always keep var.dominio.
  discovery_dominio = coalesce(var.vpc_discovery_dominio, var.dominio)

  vpc_name_to_discover = "vpc-aw-${local.region_short}-${local.discovery_dominio}-${var.ambiente}"

  # Discovered subnets by AZ letter → subnet id (populated in data.tf).
  subnet_by_az = {
    a = try(data.aws_subnet.rosa_a.id, null)
    b = try(data.aws_subnet.rosa_b.id, null)
  }

  # The union of subnets the CLUSTER is aware of (one per distinct pool AZ).
  cluster_subnet_ids = distinct([
    for mp in var.machine_pools : local.subnet_by_az[mp.subnet_az]
  ])

  # The AZ names the cluster spans — one per distinct pool AZ.
  # Map the 'a'/'b' pool selector to the discovered subnet's real AZ name.
  az_name_by_selector = {
    a = try(data.aws_subnet.rosa_a.availability_zone, null)
    b = try(data.aws_subnet.rosa_b.availability_zone, null)
  }
  cluster_availability_zones = distinct([
    for mp in var.machine_pools : local.az_name_by_selector[mp.subnet_az]
  ])

  # Machine CIDR = discovered VPC CIDR (auto-derived, never hardcoded).
  machine_cidr = data.aws_vpc.rosa.cidr_block

  # ── Mandatory tags (Tier-2) ────────────────────────────────────────────────
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    CentroCosto        = var.centro_costo
    Producto           = var.producto
    PropietarioRecurso = var.propietario_recurso
  }

  # Platform-plane metadata (auto-derived).
  platform_tags = {
    "bancointernacional.ec/plane"   = "platform"
    "bancointernacional.ec/dominio" = var.dominio
    "bancointernacional.ec/env"     = var.ambiente
    ManagedBy                       = "terraform"
  }

  tags = merge(local.mandatory_tags, local.platform_tags, var.extra_tags)

  # data.aws_caller_identity.current.arn is the STS *session* ARN, e.g.:
  #   arn:aws:sts::124355669898:assumed-role/terraform-apply-role/<SESSION>
  # The <SESSION> suffix changes every run (gha-cd-cluster, tf-plan-dev-NNNN),
  # which would cause perpetual drift if used directly. Convert to the stable
  # IAM role ARN that ROSA expects:
  #   arn:aws:iam::124355669898:role/terraform-apply-role
  _caller_arn = data.aws_caller_identity.current.arn

  rosa_creator_arn = can(regex(":assumed-role/", local._caller_arn)) ? format(
    "arn:aws:iam::%s:role/%s",
    data.aws_caller_identity.current.account_id,
    split("/", local._caller_arn)[1]   # ROLE_NAME segment
  ) : local._caller_arn
}
