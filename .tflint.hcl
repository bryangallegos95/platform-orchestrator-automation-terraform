# .tflint.hcl — Enterprise Governance Standard
#
# Distribuido desde: platform-orchestrator-automation-terraform
# Aplica a: TODOS los repos hijos que consumen los modulos transversales
#
# ENFORCEMENT:
#   - Tags mandatorios (7): Bloquea pipeline si falta alguno
#   - Naming convention: snake_case obligatorio en identificadores TF
#   - Best practices: Variables/outputs documentados, modulos estandar
#
# NOTA: Los repos hijos deben copiar este archivo o referenciarlo.
#       El CI workflow lo descarga automaticamente antes de correr tflint.
#
# ─────────────────────────────────────────────────────────────────────────────

config {
  call_module_type    = "all"
  force               = false
  disabled_by_default = false
}

# ══════════════════════════════════════════════════════════════════════════════
# PLUGIN: Terraform Language Rules
# ══════════════════════════════════════════════════════════════════════════════

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# ══════════════════════════════════════════════════════════════════════════════
# PLUGIN: AWS Rules (tflint-ruleset-aws)
# Pre-instalado en runner image. Si no, se descarga automaticamente.
# ══════════════════════════════════════════════════════════════════════════════

plugin "aws" {
  enabled = true
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
  version = "0.35.0"
}

# ══════════════════════════════════════════════════════════════════════════════
# NAMING CONVENTION — snake_case obligatorio
# ══════════════════════════════════════════════════════════════════════════════
# Aplica a: resources, data sources, variables, outputs, locals, modules
# Ejemplo valido:   aws_s3_bucket.landing_zone
# Ejemplo invalido: aws_s3_bucket.LandingZone, aws_s3_bucket.landing-zone

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# ══════════════════════════════════════════════════════════════════════════════
# MANDATORY TAGS — 7 tags requeridos en TODOS los recursos AWS que los soporten
# ══════════════════════════════════════════════════════════════════════════════
#
# Tags automaticos (inyectados via provider default_tags en terragrunt.hcl):
#   - ManagedBy    : "terraform"
#   - Repositorio  : nombre del repo (dinamico)
#   - Ambiente     : dev|qa|preprod|prod|dr (dinamico)
#
# Tags manuales (definidos en environments/{env}/terragrunt.hcl por el dev):
#   - aplicacion          : Nombre de la aplicacion (CloudOps Tier 2)
#   - propietario_recurso : Responsable tecnico del recurso
#   - producto            : Producto/area de negocio
#   - centro_costo        : Centro de costo para FinOps/CloudCheckr
#
# NOTA: Los 3 primeros se inyectan via default_tags del provider y NO aparecen
#       en el recurso individual. TFLint valida los que SI deben estar en el recurso.
#       Por lo tanto, solo validamos los 4 tags manuales que el dev DEBE definir.

rule "aws_resource_missing_tags" {
  enabled = true
  tags = [
    "Aplicacion",
    "PropietarioRecurso",
    "Producto",
    "CentroCosto",
  ]
}

# ══════════════════════════════════════════════════════════════════════════════
# BEST PRACTICES — Calidad de codigo Terraform
# ══════════════════════════════════════════════════════════════════════════════

# Variables deben tener description
rule "terraform_documented_variables" {
  enabled = true
}

# Outputs deben tener description
rule "terraform_documented_outputs" {
  enabled = true
}

# No dejar variables/locals sin usar
rule "terraform_unused_declarations" {
  enabled = true
}

# Estructura estandar de modulo (main.tf, variables.tf, outputs.tf)
rule "terraform_standard_module_structure" {
  enabled = true
}

# No usar providers deprecated
rule "terraform_deprecated_interpolation" {
  enabled = true
}
