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

variable "vpc_discovery_dominio" {
  description = <<-EOT
    Dominio used ONLY for network discovery (VPC Name + subnet dominio-tag filters)
    when the VPC naming service differs from the cluster's dominio — e.g. negocio
    clusters hosted on VPCs named vpc-aw-ue1-contenerizacion-<env>. The cluster
    itself keeps var.dominio in its tags. Null (default) = use var.dominio.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.vpc_discovery_dominio == null || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.vpc_discovery_dominio))
    error_message = "vpc_discovery_dominio must be lowercase alphanumeric/hyphen."
  }
}

# ── Machine Pools (HA via pool-per-AZ; autoscaling always on) ─────────────────
variable "machine_pools" {
  description = <<-EOT
    workers MachinePools. Each pins to ONE discovered subnet (AZ) via subnet_az
    ('a' or 'b') and autoscales between min/max replicas.

    ⚠️ NAMING CONTRACT: the first pool MUST be named "workerss".
    This is the name reserved for ROSA's auto-created default pool.
    Declaring it triggers magic import (no orphan pool). See module header.

    non-prod (single AZ):
      [{ name = "workers", subnet_az = "a", min_replicas = 2, max_replicas = 4 }]

    prod/dr (two AZs — AZ-b uses an explicit additional pool):
      [
        { name = "workers",   subnet_az = "a", min_replicas = 1, max_replicas = 2 },
        { name = "workers-b", subnet_az = "b", min_replicas = 1, max_replicas = 2 },
      ]
  EOT
  type = list(object({
    name         = string
    subnet_az    = string
    min_replicas = number
    max_replicas = number
  }))

  # ── Structural validations ─────────────────────────────────────────────────
  validation {
    condition     = length(var.machine_pools) > 0
    error_message = "At least one machine pool is required."
  }

  validation {
    condition     = alltrue([for mp in var.machine_pools : contains(["a", "b"], mp.subnet_az)])
    error_message = "Each machine_pools[].subnet_az must be 'a' or 'b'."
  }

  validation {
    condition     = alltrue([for mp in var.machine_pools : mp.min_replicas >= 1 && mp.max_replicas >= mp.min_replicas])
    error_message = "min_replicas >= 1 and max_replicas >= min_replicas for every pool."
  }

  # ── Magic-import contract (v1.9.0) ─────────────────────────────────────────
  # First pool must claim the reserved default-pool name so the provider fires
  # the import path instead of creating a second pool. The length==0 guard
  # prevents an index-out-of-bounds if the structural validation above fails first.
  validation {
    condition     = length(var.machine_pools) == 0 || var.machine_pools[0].name == "workers"
    error_message = "The first machine pool MUST be named 'workers' — the ROSA reserved default pool name. Any other name creates an orphan. See module header in main.tf."
  }

  # Additional pools must NOT steal the reserved name; "workers" is exclusively
  # for the default pool. Only index 0 is allowed to carry that name.
  validation {
    condition     = alltrue([for i, mp in var.machine_pools : i == 0 || mp.name != "workers"])
    error_message = "Only the first pool may be named 'workers'. Additional pools must use a different name (e.g., 'workers-b' for AZ-b in prod/dr)."
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

# ── Control-Plane PrivateLink Endpoint — additional Security Group ────────────
variable "cp_ingress_cidrs" {
  description = <<-EOT
    CIDR blocks allowed HTTPS (port 443) inbound access to the ROSA HCP
    Control-Plane PrivateLink Endpoint. Each CIDR generates an independent
    aws_vpc_security_group_ingress_rule on a dedicated Security Group that is
    additively associated with the API VPC endpoint.

    Leave empty (default) to skip SG creation entirely — useful when access
    is already covered by the VPC default SG or TGW security policies.

    Bank-standard values (set in ALL cluster invocations):
      ["10.0.0.0/8", "172.16.0.0/16", "172.27.0.0/16"]

    Requires ROSA >= 4.17.2 (fleet standard: 4.20.25 ✅).
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.cp_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "All entries in cp_ingress_cidrs must be valid CIDR blocks (e.g. '10.0.0.0/8')."
  }
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
