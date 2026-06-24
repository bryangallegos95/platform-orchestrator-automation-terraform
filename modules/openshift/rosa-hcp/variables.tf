# modules/openshift/rosa-hcp/variables.tf
#
# Inputs for a single ROSA HCP cluster. Subnets are DISCOVERED by tag (Option 3) —
# no subnet IDs are passed. Machine CIDR is auto-derived from the discovered VPC.

# ── Identity ──────────────────────────────────────────────────────────────────
variable "cluster_name" {
  description = "ROSA HCP cluster name. E.g. 'int-dev'. Lowercase, <=54 chars, start with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,52}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase alphanumeric/hyphen and start with a letter."
  }
}

variable "dominio" {
  description = "Platform domain — integracion | negocio. Used for subnet discovery and naming."
  type        = string

  validation {
    condition     = contains(["integracion", "negocio"], var.dominio)
    error_message = "dominio must be 'integracion' or 'negocio'."
  }
}

variable "ambiente" {
  description = "Environment — dev|qa|preprod|prod|dr. Used for subnet discovery and naming."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "preprod", "prod", "dr"], var.ambiente)
    error_message = "ambiente must be one of: dev, qa, preprod, prod, dr."
  }
}

variable "aws_region" {
  description = "AWS region. us-east-1 (primary/prod) or us-east-2 (DR)."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.aws_region)
    error_message = "aws_region must be us-east-1 or us-east-2."
  }
}

variable "aws_account_id" {
  description = "Target AWS account ID — provided by GitHub workflow_dispatch. Cluster + tagged subnets MUST live in this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ── KMS (EBS default-encryption CMK the workers/CSI must use) ─────────────────
variable "ebs_kms_key_arn" {
  description = <<-EOT
    ARN of the customer-managed KMS key used for EBS default encryption in this
    account. The module creates aws_kms_grants so the ROSA worker + operator
    roles can use it (required when EbsEncryptionByDefault uses a CMK).

    - integracion: pass the SHARED key ARN (same for all integracion clusters).
    - negocio:     pass the cluster's INDIVIDUAL key ARN.
    - "" (empty)   => no grants (only when EBS uses the AWS-managed aws/ebs key).
  EOT
  type    = string
  default = ""
}

# ── OpenShift (fleet pin) ─────────────────────────────────────────────────────
variable "openshift_version" {
  description = "Exact OpenShift Z-stream. Fleet pin 4.20.25. MUST be ROSA-HCP-available — verify with 'rosa list versions --hosted-cp'."
  type        = string
  default     = "4.20.25"

  validation {
    condition     = can(regex("^4\\.20\\.[0-9]+$", var.openshift_version))
    error_message = "openshift_version must be a 4.20.z release (fleet standard pin: 4.20.25)."
  }
}

# ── Account roles (from account-bootstrap) ────────────────────────────────────
variable "account_role_prefix" {
  description = "Prefix of the SHARED account roles created by account-bootstrap in this account."
  type        = string
  default     = "bin-rosa-hcp"
}

# ── Subnet discovery (Option 3 — tag based) ───────────────────────────────────
variable "rosa_subnet_discovery_tag" {
  description = "Tag key marking ROSA-eligible private subnets (matches the VPC module contract)."
  type        = string
  default     = "bancointernacional.ec/rosa"
}

# ── Machine Pools (HA via pool-per-AZ; autoscaling always on) ─────────────────
variable "machine_pools" {
  description = <<-EOT
    Worker MachinePools. Each pins to ONE discovered subnet (AZ) via subnet_az
    ('a' or 'b') and autoscales between min/max.

    non-prod (single AZ):
      [{ name = "default", subnet_az = "a", min_replicas = 2, max_replicas = 4 }]

    prod/dr (two AZs):
      [
        { name = "az-a", subnet_az = "a", min_replicas = 1, max_replicas = 2 },
        { name = "az-b", subnet_az = "b", min_replicas = 1, max_replicas = 2 },
      ]
  EOT
  type = list(object({
    name         = string
    subnet_az    = string
    min_replicas = number
    max_replicas = number
  }))

  validation {
    condition     = length(var.machine_pools) > 0
    error_message = "At least one machine pool is required."
  }
  validation {
    condition     = alltrue([for mp in var.machine_pools : contains(["a", "b"], mp.subnet_az)])
    error_message = "each machine_pools[].subnet_az must be 'a' or 'b'."
  }
  validation {
    condition     = alltrue([for mp in var.machine_pools : mp.min_replicas >= 1 && mp.max_replicas >= mp.min_replicas])
    error_message = "min_replicas >= 1 and max_replicas >= min_replicas for every pool."
  }
}

variable "compute_machine_type" {
  description = "EC2 instance type for worker nodes. Fleet default m6a.xlarge."
  type        = string
  default     = "m6a.xlarge"
}
# ── Instance hardening ────────────────────────────────────────────────────────
variable "ec2_metadata_http_tokens" {
  description = "IMDS mode. 'required' = IMDSv2 only (recommended/bank standard). 'optional' = IMDSv1+v2."
  type        = string
  default     = "required"

  validation {
    condition     = contains(["required", "optional"], var.ec2_metadata_http_tokens)
    error_message = "ec2_metadata_http_tokens must be 'required' or 'optional'."
  }
}

variable "worker_disk_size" {
  description = "Worker node root disk size in GiB. Fleet default 120 (dev). ROSA hard default is 300."
  type        = number
  default     = 120

  validation {
    condition     = var.worker_disk_size >= 75 && var.worker_disk_size <= 16384
    error_message = "worker_disk_size must be between 75 and 16384 GiB."
  }
}
# ── Networking (machine CIDR auto-derived from VPC; pod/service = ROSA default) ─
variable "pod_cidr" {
  description = "Pod CIDR (ROSA default 10.128.0.0/14). Must not overlap VPC/machine CIDR."
  type        = string
  default     = "10.128.0.0/14"
}

variable "service_cidr" {
  description = "Service CIDR (ROSA default 172.30.0.0/16). Must not overlap VPC/machine CIDR."
  type        = string
  default     = "172.30.0.0/16"
}

variable "host_prefix" {
  description = "Pod subnet prefix per node (ROSA default 23)."
  type        = number
  default     = 23
}

# ── Mandatory tags (org contract — all four required, no defaults) ────────────
variable "aplicacion" {
  description = "[MANDATORY TAG] Application that owns this resource."
  type        = string
  validation {
    condition     = length(trimspace(var.aplicacion)) > 0
    error_message = "aplicacion (mandatory tag) must not be empty."
  }
}

variable "centro_costo" {
  description = "[MANDATORY TAG] Cost center code for billing allocation."
  type        = string
  validation {
    condition     = length(trimspace(var.centro_costo)) > 0
    error_message = "centro_costo (mandatory tag) must not be empty."
  }
}

variable "producto" {
  description = "[MANDATORY TAG] Product / business unit."
  type        = string
  validation {
    condition     = length(trimspace(var.producto)) > 0
    error_message = "producto (mandatory tag) must not be empty."
  }
}

variable "propietario_recurso" {
  description = "[MANDATORY TAG] Resource owner (team or person)."
  type        = string
  validation {
    condition     = length(trimspace(var.propietario_recurso)) > 0
    error_message = "propietario_recurso (mandatory tag) must not be empty."
  }
}

variable "extra_tags" {
  description = "Optional additional tags merged after the mandatory four."
  type        = map(string)
  default     = {}
}
