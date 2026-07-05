# modules/database/aurora-postgresql/variables.tf
#
# Inputs for an Aurora PostgreSQL cluster deployed into an existing Spoke VPC.
# The VPC, BDD subnets and RDS CMK are DISCOVERED by the tag/naming/alias
# contract — no IDs are passed in; no shared state.
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
  description = "Short service / product name used in resource naming AND VPC discovery. Must match the 'service' used by the Spoke VPC module (vpc-aw-{region}-{service}-{ambiente}). E.g. 'payments', 'devops', 'bff'"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service))
    error_message = "service must be lowercase alphanumeric and hyphens only."
  }
}

variable "workload" {
  description = "Short name of THIS database workload within the service — used as the name suffix. E.g. 'core', 'ledger', 'clientes'. Call the module once per cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workload))
    error_message = "workload must be lowercase alphanumeric and hyphens only."
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

variable "aws_account_id" {
  description = "Target AWS account ID — provided by GitHub workflow_dispatch. Cluster + discovered VPC/KMS MUST live in this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ── Engine ────────────────────────────────────────────────────────────────────
variable "engine_version" {
  description = "Aurora PostgreSQL engine version (e.g. '16.6'). The parameter-group family is derived from the major version unless db_family is set."
  type        = string
  default     = "16.6"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be MAJOR.MINOR (e.g. '16.6')."
  }
}

variable "db_family" {
  description = "Parameter-group family override (e.g. 'aurora-postgresql15'). \"\" (empty) => derived from engine_version major ('aurora-postgresql16' for 16.x). Change family + engine_version together to move engine generations."
  type        = string
  default     = ""

  validation {
    condition     = var.db_family == "" || can(regex("^aurora-postgresql[0-9]+$", var.db_family))
    error_message = "db_family must be empty or 'aurora-postgresql<major>' (e.g. aurora-postgresql16)."
  }
}

variable "database_name" {
  description = "Optional initial database created in the cluster. \"\" (empty) => no initial database. Ignored on global-secondary (dr) clusters."
  type        = string
  default     = ""

  validation {
    condition     = var.database_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "database_name must start with a letter and contain only alphanumerics/underscores."
  }
}

# ── Admin service user (day-1/day-2 credential — lives in BeyondTrust) ────────
variable "master_username" {
  description = "Admin service user of the cluster. Must match the username registered in BeyondTrust Secrets Safe for this cluster."
  type        = string
  default     = "svcadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,31}$", var.master_username)) && !contains(["postgres", "admin", "rdsadmin"], var.master_username)
    error_message = "master_username must be 3-32 chars, start with a letter, lowercase alphanumeric/underscore, and not a reserved name (postgres, admin, rdsadmin)."
  }
}

variable "master_password" {
  description = "Admin service user password. SENSITIVE — NEVER hardcode. Injected by ci.yml as TF_VAR_master_password from BeyondTrust Secrets Safe (secret_titles input). Not used on global-secondary (dr) clusters."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.master_password == "" || length(var.master_password) >= 16
    error_message = "master_password must be at least 16 characters (BeyondTrust-generated)."
  }
}

# ── Topology ──────────────────────────────────────────────────────────────────
variable "multi_az" {
  description = "Deploy writer + reader across AZs (auto-failover). null = auto: multi-AZ in prod/dr, single-AZ in dev/qa/preprod."
  type        = bool
  default     = null
}

variable "instance_class" {
  description = "Default DB instance class for cluster instances (Graviton recommended). Per-instance override via var.instances."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be a valid RDS instance class (e.g. db.r6g.large)."
  }
}

variable "instances" {
  description = <<-EOT
    Explicit instance topology — REPLACES the environment default when set.
    Keys become the instance name suffix; null fields fall back to module
    defaults. Use this from son repos to ADD readers or CHANGE the class of
    a single instance.

    Example (prod: writer + 2 readers, one bigger for analytics):
      {
        "01"        = { az = "a", promotion_tier = 0 }
        "02"        = { az = "b", promotion_tier = 1 }
        "analytics" = { az = "b", promotion_tier = 15, instance_class = "db.r6g.2xlarge" }
      }
  EOT
  type = map(object({
    instance_class = optional(string)
    az             = optional(string, "a")
    promotion_tier = optional(number, 1)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.instances : contains(["a", "b"], coalesce(v.az, "a"))])
    error_message = "Every instances[].az must be 'a' or 'b'."
  }

  validation {
    condition     = alltrue([for k, v in var.instances : can(regex("^[a-z0-9]+$", k))])
    error_message = "Instance keys must be lowercase alphanumeric (they become name suffixes)."
  }
}

# ── Global Database (prod ↔ dr replication, opt-in) ───────────────────────────
variable "enable_global_database" {
  description = "PROD only: create an Aurora Global Database FROM this cluster (no recreation). The dr environment then joins it via global_cluster_identifier."
  type        = bool
  default     = false
}

variable "global_cluster_identifier" {
  description = "DR only: identifier of the existing Global Database to join as a read-replica secondary (gdb-aw-{service}-{workload}). \"\" (empty) => standalone mirror cluster (default, matches the validated DR flow)."
  type        = string
  default     = ""
}

# ── KMS (existing account CMK for RDS) ────────────────────────────────────────
variable "kms_key_alias" {
  description = "Alias of the account's pre-existing RDS CMK, discovered at plan time. The module NEVER creates keys."
  type        = string
  default     = "alias/rds"

  validation {
    condition     = can(regex("^alias/", var.kms_key_alias))
    error_message = "kms_key_alias must start with 'alias/'."
  }
}

variable "kms_key_arn" {
  description = "Explicit KMS key ARN override. \"\" (empty) => discover by kms_key_alias."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a valid KMS key ARN."
  }
}

variable "kms_consumer_role_arns" {
  description = <<-EOT
    Map of IAM role ARNs (lambda/ecs/eks/ec2 workload roles) that get an
    ADDITIVE KMS grant to use the RDS CMK (snapshots exported to S3,
    Performance Insights reads...). Keys are short labels used in the grant
    name. Does NOT modify the key policy.

    Example:
      { "lambda-etl" = "arn:aws:iam::111122223333:role/lambda-etl-role" }
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, arn in var.kms_consumer_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/", arn))])
    error_message = "Every kms_consumer_role_arns value must be an IAM role ARN."
  }
}

# ── Network access (default: no inbound) ──────────────────────────────────────
variable "allowed_security_group_ids" {
  description = "Consumer Security Group IDs granted 5432/tcp (preferred over CIDRs — grants by workload identity). Default [] = no inbound."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.allowed_security_group_ids : can(regex("^sg-", id))])
    error_message = "Every allowed_security_group_ids entry must be a Security Group ID (sg-...)."
  }
}

variable "allowed_cidrs" {
  description = <<-EOT
    CIDR blocks granted 5432/tcp (e.g. app-tier subnets). Default [] = no inbound.

    Example:
      [{ description = "App tier subnets", cidr = "10.10.0.0/24" }]
  EOT
  type = list(object({
    description = string
    cidr        = string
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.allowed_cidrs : can(cidrnetmask(r.cidr))])
    error_message = "Every allowed_cidrs[].cidr must be a valid CIDR block (e.g. '10.0.0.0/8')."
  }
}

variable "additional_security_group_ids" {
  description = "Optional extra Security Group IDs to attach to the cluster in addition to the module-managed SG."
  type        = list(string)
  default     = []
}

# ── Backups / protection ──────────────────────────────────────────────────────
variable "backup_retention_period" {
  description = "Automated backup retention in days. null = auto: 35 in prod/dr, 7 elsewhere."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_period == null || try(var.backup_retention_period >= 7 && var.backup_retention_period <= 35, false)
    error_message = "backup_retention_period must be between 7 and 35 days (bank baseline: never below 7)."
  }
}

variable "preferred_backup_window" {
  description = "Daily backup window (UTC), outside business hours."
  type        = string
  default     = "04:00-05:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC)."
  type        = string
  default     = "sun:05:30-sun:07:00"
}

variable "deletion_protection" {
  description = "Protect the cluster from deletion. null = auto: enabled in preprod/prod/dr, disabled in dev/qa."
  type        = bool
  default     = null
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of waiting for the maintenance window. null = auto: true in dev/qa, false in preprod/prod/dr."
  type        = bool
  default     = null
}

# ── Observability ─────────────────────────────────────────────────────────────
variable "performance_insights_enabled" {
  description = "Enable Performance Insights (encrypted with the same RDS CMK)."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days (7 = free tier; 731 = 2 years)."
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be 7, 731, or a multiple of 31 up to 713."
  }
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring granularity in seconds (0 = off). null = auto: 60 in preprod/prod/dr, 0 in dev/qa."
  type        = number
  default     = null

  validation {
    condition     = var.monitoring_interval == null || try(contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval), false)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "ca_cert_identifier" {
  description = "CA certificate bundle for the DB instances."
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

# ── Parameter overrides (son-repo tuning) ─────────────────────────────────────
variable "cluster_parameters" {
  description = <<-EOT
    Extra cluster-level parameters merged OVER the security baseline (your
    entries win on name collision — the baseline names are: rds.force_ssl,
    log_connections, log_disconnections, log_statement,
    log_min_duration_statement, shared_preload_libraries, pgaudit.log).

    Example:
      [{ name = "max_connections", value = "500", apply_method = "pending-reboot" }]
  EOT
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []

  validation {
    condition     = alltrue([for p in var.cluster_parameters : contains(["immediate", "pending-reboot"], coalesce(p.apply_method, "immediate"))])
    error_message = "Every cluster_parameters[].apply_method must be 'immediate' or 'pending-reboot'."
  }
}

variable "instance_parameters" {
  description = "Instance-level (DB parameter group) parameters. Same shape as cluster_parameters."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []

  validation {
    condition     = alltrue([for p in var.instance_parameters : contains(["immediate", "pending-reboot"], coalesce(p.apply_method, "immediate"))])
    error_message = "Every instance_parameters[].apply_method must be 'immediate' or 'pending-reboot'."
  }
}

# ── Mandatory Tags ────────────────────────────────────────────────────────────
# All four tags are REQUIRED — no default values intentionally.

variable "aplicacion" {
  description = "[MANDATORY TAG] Name of the application that owns this cluster."
  type        = string

  validation {
    condition     = length(trimspace(var.aplicacion)) > 0
    error_message = "aplicacion (mandatory tag) must not be empty."
  }
}

variable "propietario_recurso" {
  description = "[MANDATORY TAG] Resource owner (team or person responsible)."
  type        = string

  validation {
    condition     = length(trimspace(var.propietario_recurso)) > 0
    error_message = "propietario_recurso (mandatory tag) must not be empty."
  }
}

variable "producto" {
  description = "[MANDATORY TAG] Product or business unit that this cluster belongs to."
  type        = string

  validation {
    condition     = length(trimspace(var.producto)) > 0
    error_message = "producto (mandatory tag) must not be empty."
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

variable "extra_tags" {
  description = "Optional additional tags to merge with the mandatory tag set."
  type        = map(string)
  default     = {}
}
