# modules/openshift/rosa-hcp/locals.tf
#
# Naming + tag factory — mirrors the VPC module convention.
#   region_short: ue1 (us-east-1) | ue2 (us-east-2)
#   VPC name to discover: vpc-aw-{region_short}-{dominio}-{ambiente}

locals {
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  vpc_name_to_discover = "vpc-aw-${local.region_short}-${var.dominio}-${var.ambiente}"

  # Discovered subnets by AZ letter → subnet id (populated in data.tf).
  subnet_by_az = {
    a = try(data.aws_subnet.rosa_a.id, null)
    b = try(data.aws_subnet.rosa_b.id, null)
  }

  # The union of subnets the CLUSTER is aware of (one per distinct pool AZ).
  cluster_subnet_ids = distinct([
    for mp in var.machine_pools : local.subnet_by_az[mp.subnet_az]
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
}
