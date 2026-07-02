# modules/compute/ec2/locals.tf
#
# Centralised naming convention and tag factory — mirrors the VPC module.
# ALL resource names are derived from here — never hardcoded in main.tf.
#
# Naming pattern reference:
#   Instance    : ec2-aw-{region_short}-{service}-{workload}-{ambiente}
#   Root volume : ebs-aw-{region_short}-{service}-{workload}-root-{ambiente}
#   SG          : sgp-aw-{region_short}-{service}-{workload}-{ambiente}
#   IAM Role    : iam-role-aw-{region_short}-{service}-{workload}-ec2-{ambiente}
#   Profile     : iam-prof-aw-{region_short}-{service}-{workload}-ec2-{ambiente}
#   VPC lookup  : vpc-aw-{region_short}-{service}-{ambiente}

locals {
  # ── Region-derived values ────────────────────────────────────────────────
  region_short = var.aws_region == "us-east-2" ? "ue2" : "ue1"

  # ── Discovery targets (contract with modules/networking/vpc) ─────────────
  vpc_name_to_discover = "vpc-aw-${local.region_short}-${var.service}-${var.ambiente}"

  # ── Resource names ────────────────────────────────────────────────────────
  instance_name         = "ec2-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  root_volume_name      = "ebs-aw-${local.region_short}-${var.service}-${var.workload}-root-${var.ambiente}"
  sg_name               = "sgp-aw-${local.region_short}-${var.service}-${var.workload}-${var.ambiente}"
  iam_role_name         = "iam-role-aw-${local.region_short}-${var.service}-${var.workload}-ec2-${var.ambiente}"
  instance_profile_name = "iam-prof-aw-${local.region_short}-${var.service}-${var.workload}-ec2-${var.ambiente}"

  # ── AMI resolution ────────────────────────────────────────────────────────
  # Explicit ami_id wins; otherwise resolve the latest AMI from the SSM
  # public parameter (see data.tf). main.tf ignores AMI drift after creation.
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.ami[0].value

  # ── Termination protection ────────────────────────────────────────────────
  # Explicit input wins; null = auto → protected in preprod/prod/dr.
  termination_protection = (
    var.enable_termination_protection != null
    ? var.enable_termination_protection
    : contains(["preprod", "prod", "dr"], var.ambiente)
  )

  # ── Tag factory ─────────────────────────────────────────────────────────
  mandatory_tags = {
    Aplicacion         = var.aplicacion
    PropietarioRecurso = var.propietario_recurso
    Producto           = var.producto
    CentroCosto        = var.centro_costo
    Ambiente           = var.ambiente
    ManagedBy          = "terraform"
  }

  # Final merged tag map — used everywhere
  tags = merge(local.mandatory_tags, var.extra_tags)
}
