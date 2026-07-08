# modules/networking/palo-alto-vmseries/main.tf
#
# Data sources and locals for the Palo Alto VM-Series module.
# This module deploys PA-VM behind a Gateway Load Balancer with Auto Scaling.

data "aws_caller_identity" "current" {}

data "aws_subnet" "data" {
  count = length(var.data_subnet_ids)
  id    = var.data_subnet_ids[count.index]
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  common_tags = merge(
    {
      Aplicacion         = var.aplicacion
      PropietarioRecurso = var.propietario_recurso
      Producto           = var.producto
      CentroCosto        = var.centro_costo
      Module             = "palo-alto-vmseries"
      Ambiente           = var.ambiente
    },
    var.extra_tags
  )

  # Derive AZs from the data subnets for consistent placement
  az_ids = [for s in data.aws_subnet.data : s.availability_zone_id]

  # Bootstrap user-data string (PA init-cfg format)
  bootstrap_user_data = join(";", compact([
    "mgmt-interface-swap=${var.bootstrap_options.mgmt_interface_swap}",
    "plugin-op-commands=${var.bootstrap_options.plugin_op_commands}",
    var.bootstrap_options.panorama_server != "" ? "panorama-server=${var.bootstrap_options.panorama_server}" : "",
    var.bootstrap_options.auth_key != "" ? "auth-key=${var.bootstrap_options.auth_key}" : "",
    "dgname=${var.bootstrap_options.dgname}",
    var.bootstrap_options.tplname != "" ? "tplname=${var.bootstrap_options.tplname}" : "",
    "dhcp-send-hostname=${var.bootstrap_options.dhcp_send_hostname}",
    "dhcp-send-client-id=${var.bootstrap_options.dhcp_send_client_id}",
    "dhcp-accept-server-hostname=${var.bootstrap_options.dhcp_accept_server_hostname}",
    "dhcp-accept-server-domain=${var.bootstrap_options.dhcp_accept_server_domain}",
    var.create_bootstrap_bucket ? "vmseries-bootstrap-aws-s3bucket=${aws_s3_bucket.bootstrap[0].id}" : (var.bootstrap_bucket_name != "" ? "vmseries-bootstrap-aws-s3bucket=${var.bootstrap_bucket_name}" : ""),
  ]))
}
