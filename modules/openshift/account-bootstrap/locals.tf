# modules/openshift/account-bootstrap/locals.tf

locals {
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    CentroCosto        = var.centro_costo
    Producto           = var.producto
    PropietarioRecurso = var.propietario_recurso
  }

  tags = merge(local.mandatory_tags, var.extra_tags, {
    ManagedBy = "terraform"
  })
}
