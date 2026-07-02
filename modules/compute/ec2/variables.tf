# modules/compute/ec2/variables.tf
#
# Inputs for a single EC2 instance deployed into an existing Spoke VPC.
# The VPC and subnet are DISCOVERED by the tag/naming contract stamped by
# modules/networking/vpc — no VPC/subnet IDs are passed in; no shared state.
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
  description = "Short name of THIS EC2 workload within the service — used as the name suffix. E.g. 'bastion', 'sftp', 'app01'. Call the module once per instance."
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
  description = "Target AWS account ID — provided by GitHub workflow_dispatch. Instance + discovered VPC MUST live in this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# ── Placement (subnet discovery — tag based) ──────────────────────────────────
variable "subnet_tier" {
  description = "Subnet tier of the Spoke VPC to place the instance in: app | bdd | gwlb. Matches the 'Tier' tag stamped by the VPC module."
  type        = string
  default     = "app"

  validation {
    condition     = contains(["app", "bdd", "gwlb"], var.subnet_tier)
    error_message = "subnet_tier must be one of: app, bdd, gwlb."
  }
}

variable "subnet_az" {
  description = "AZ selector for placement: 'a' or 'b'. Matches the 'AZ' tag stamped by the VPC module."
  type        = string
  default     = "a"

  validation {
    condition     = contains(["a", "b"], var.subnet_az)
    error_message = "subnet_az must be 'a' or 'b'."
  }
}

# ── Instance ──────────────────────────────────────────────────────────────────
variable "instance_type" {
  description = "EC2 instance type. Fleet default t3.medium."
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium, m6a.xlarge)."
  }
}

variable "ami_id" {
  description = "Explicit AMI ID (e.g. a hardened golden AMI). Leave empty to resolve the latest AMI from ami_ssm_parameter."
  type        = string
  default     = ""

  validation {
    condition     = var.ami_id == "" || can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be empty or a valid AMI ID (e.g. ami-0abc1234)."
  }
}

variable "ami_ssm_parameter" {
  description = "SSM public parameter used to resolve the AMI when ami_id is empty. Default: latest Amazon Linux 2023 x86_64."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "user_data" {
  description = "Optional cloud-init user data script. Leave null for none."
  type        = string
  default     = null
}

variable "key_name" {
  description = "Optional EC2 key pair name. Default null — access is via SSM Session Manager (bank standard), no SSH keys."
  type        = string
  default     = null
}

variable "enable_detailed_monitoring" {
  description = "Enable CloudWatch detailed (1-minute) monitoring."
  type        = bool
  default     = false
}

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection (disable_api_termination). null = auto: enabled in preprod/prod/dr, disabled in dev/qa."
  type        = bool
  default     = null
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

# ── Root volume ───────────────────────────────────────────────────────────────
variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 50

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384
    error_message = "root_volume_size must be between 8 and 16384 GiB."
  }
}

variable "root_volume_type" {
  description = "Root EBS volume type."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be one of: gp3, gp2, io1, io2."
  }
}

# ── KMS (EBS encryption CMK) ──────────────────────────────────────────────────
variable "ebs_kms_key_arn" {
  description = <<-EOT
    ARN of the customer-managed KMS key used to encrypt the root EBS volume.
    "" (empty) => rely on the account's EBS default-encryption key.
    Encryption itself is ALWAYS on — this only selects the key.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.ebs_kms_key_arn == "" || can(regex("^arn:aws:kms:", var.ebs_kms_key_arn))
    error_message = "ebs_kms_key_arn must be empty or a valid KMS key ARN."
  }
}

# ── Security Group ────────────────────────────────────────────────────────────
variable "ingress_rules" {
  description = <<-EOT
    Inbound rules for the instance's dedicated Security Group. Each entry
    generates an independent aws_vpc_security_group_ingress_rule.
    Default = [] (no inbound — SSM Session Manager needs none).

    Example:
      [{ description = "HTTPS from spokes", cidr = "172.27.0.0/16", from_port = 443, to_port = 443, protocol = "tcp" }]
  EOT
  type = list(object({
    description = string
    cidr        = string
    from_port   = number
    to_port     = number
    protocol    = string
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.ingress_rules : can(cidrnetmask(r.cidr))])
    error_message = "Every ingress_rules[].cidr must be a valid CIDR block (e.g. '10.0.0.0/8')."
  }
}

variable "additional_security_group_ids" {
  description = "Optional extra Security Group IDs to attach in addition to the module-managed SG."
  type        = list(string)
  default     = []
}

# ── IAM ───────────────────────────────────────────────────────────────────────
variable "additional_iam_policy_arns" {
  description = "Optional extra IAM managed policy ARNs to attach to the instance role (AmazonSSMManagedInstanceCore is always attached)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.additional_iam_policy_arns : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/", arn))])
    error_message = "Every additional_iam_policy_arns entry must be a valid IAM policy ARN."
  }
}

# ── Mandatory Tags ────────────────────────────────────────────────────────────
# All four tags are REQUIRED — no default values intentionally.

variable "aplicacion" {
  description = "[MANDATORY TAG] Name of the application that owns this instance."
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
  description = "[MANDATORY TAG] Product or business unit that this instance belongs to."
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
