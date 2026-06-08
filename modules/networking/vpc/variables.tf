# modules/networking/vpc/variables.tf
#
# All inputs for the Spoke VPC module.
# CIDRs come from Port.io via the caller workflow (terraform.tfvars).
# Mandatory tags are enforced at the variable level — no default values.
# ── Region ───────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region where resources will be created. Used by the provider block generated in root terragrunt.hcl."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 (primary) or us-east-2 (DR). No other regions are enabled."
  }
}
# ── Identity ──────────────────────────────────────────────────────────────────
variable "service" {
  description = "Short service / product name used in resource naming. E.g. 'payments', 'devops', 'bff'"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service))
    error_message = "service must be lowercase alphanumeric and hyphens only."
  }
}

variable "ambiente" {
  description = "Environment name. Must match one of the known branches: dev | qa | preprod | prod | dr"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "preprod", "prod", "dr"], var.ambiente)
    error_message = "ambiente must be one of: dev, qa, preprod, prod, dr."
  }
}

# ── VPC CIDR ──────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the spoke VPC. Provided by Port.io. E.g. 10.10.0.0/22"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

# ── Subnet CIDRs — App tier ───────────────────────────────────────────────────
variable "subnet_app_a_cidr" {
  description = "CIDR for private App subnet in AZ-a (us-east-1a / use1-az1). Provided by Port.io."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.subnet_app_a_cidr))
    error_message = "subnet_app_a_cidr must be a valid CIDR block."
  }
}

variable "subnet_app_b_cidr" {
  description = "CIDR for private App subnet in AZ-b (us-east-1b / use1-az2). Provided by Port.io."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.subnet_app_b_cidr))
    error_message = "subnet_app_b_cidr must be a valid CIDR block."
  }
}

# ── Subnet CIDRs — BDD (database) tier ───────────────────────────────────────
variable "subnet_bdd_a_cidr" {
  description = "CIDR for private BDD (database) subnet in AZ-a. Provided by Port.io."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.subnet_bdd_a_cidr))
    error_message = "subnet_bdd_a_cidr must be a valid CIDR block."
  }
}

variable "subnet_bdd_b_cidr" {
  description = "CIDR for private BDD (database) subnet in AZ-b. Provided by Port.io."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.subnet_bdd_b_cidr))
    error_message = "subnet_bdd_b_cidr must be a valid CIDR block."
  }
}

# ── Subnet CIDRs — GWLB / API GW tier ────────────────────────────────────────
variable "subnet_gwlb_a_cidr" {
  description = "CIDR for private GWLB / API-GW endpoint subnet in AZ-a. Provided by Port.io."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.subnet_gwlb_a_cidr))
    error_message = "subnet_gwlb_a_cidr must be a valid CIDR block."
  }
}

variable "subnet_gwlb_b_cidr" {
  description = "CIDR for private GWLB / API-GW endpoint subnet in AZ-b. Provided by Port.io."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.subnet_gwlb_b_cidr))
    error_message = "subnet_gwlb_b_cidr must be a valid CIDR block."
  }
}

# ── Transit Gateway ───────────────────────────────────────────────────────────
variable "tgw_id" {
  description = "Transit Gateway ID in the Hub (networking) account. This VPC will be attached to it."
  type        = string

  validation {
    condition     = can(regex("^tgw-[0-9a-f]+$", var.tgw_id))
    error_message = "tgw_id must be a valid TGW ID (e.g. tgw-0abc1234)."
  }
}

variable "tgw_route_table_id" {
  description = "Optional: TGW route table ID for explicit association and propagation. If null, TGW default route table is used."
  type        = string
  default     = null
}

# ── VPC Flow Logs ─────────────────────────────────────────────────────────────
variable "flow_log_retention_days" {
  description = "CloudWatch Log Group retention period in days for VPC Flow Logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a value accepted by CloudWatch (e.g. 7, 14, 30, 60, 90, 365)."
  }
}

variable "flow_log_traffic_type" {
  description = "Traffic type to capture in Flow Logs: ALL | ACCEPT | REJECT"
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ALL, ACCEPT, or REJECT."
  }
}

# ── Mandatory Tags ────────────────────────────────────────────────────────────
# All four tags are REQUIRED — no default values intentionally.

variable "aplicacion" {
  description = "[MANDATORY TAG] Name of the application that owns this VPC."
  type        = string
}

variable "propietario_recurso" {
  description = "[MANDATORY TAG] Resource owner (team or person responsible)."
  type        = string
}

variable "producto" {
  description = "[MANDATORY TAG] Product or business unit that this VPC belongs to."
  type        = string
}

variable "centro_costo" {
  description = "[MANDATORY TAG] Cost center code for billing allocation."
  type        = string
}

variable "extra_tags" {
  description = "Optional additional tags to merge with the mandatory tag set."
  type        = map(string)
  default     = {}
}
