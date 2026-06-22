# modules/networking/centralized-endpoints/locals.tf

locals {
  region_short = replace(replace(var.aws_region, "us-east-1", "ue1"), "us-east-2", "ue2")

  tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
  }

  # ── Spoke association account split (v1.3.1) ─────────────────────────
  # Each entry in var.spoke_vpc_associations now carries an account_id.
  # If it equals var.hub_account_id → SAME account (direct zone association).
  # Otherwise → CROSS account (authorization only; spoke accepts separately).
  #
  # Back-compat: account_id is optional. When omitted (null), we assume the
  # spoke is in the hub account (the v1.3.0 effective behavior for the only
  # spoke that ever worked — a same-account VPC), so existing call sites that
  # don't yet set account_id still resolve to the SAME-account path, which is
  # the correct fix for integracion-dev.
  _assoc_pairs = {
    for pair in setproduct(var.endpoints, var.spoke_vpc_associations) :
    "${pair[0]}-${pair[1].vpc_id}" => {
      endpoint   = pair[0]
      vpc_id     = pair[1].vpc_id
      region     = pair[1].region
      account_id = coalesce(pair[1].account_id, var.hub_account_id)
    }
  }

  same_account_associations = {
    for k, v in local._assoc_pairs : k => v
    if v.account_id == var.hub_account_id
  }

  cross_account_associations = {
    for k, v in local._assoc_pairs : k => v
    if v.account_id != var.hub_account_id
  }
}
