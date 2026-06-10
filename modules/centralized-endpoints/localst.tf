locals {
  region_short = var.aws_region == "us-east-1" ? "ue1" : "ue2"

  tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
  }
}
