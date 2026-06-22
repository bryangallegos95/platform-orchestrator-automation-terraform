# modules/networking/centralized-endpoints/variables.tf

variable "vpc_id" {
  description = "Egress VPC ID where endpoints will be deployed."
  type        = string
}

variable "vpc_cidr" {
  description = "Egress VPC CIDR block."
  type        = string
}

variable "tgw_id" {
  description = "Transit Gateway ID for return routes to spokes."
  type        = string
}

variable "endpoint_subnet_a_cidr" {
  description = "CIDR for new endpoint subnet in AZ-a."
  type        = string
}

variable "endpoint_subnet_b_cidr" {
  description = "CIDR for new endpoint subnet in AZ-b."
  type        = string
}

variable "az_id_a" {
  description = "AZ ID for zone A (e.g., use1-az1)."
  type        = string
  default     = "use1-az1"
}

variable "az_id_b" {
  description = "AZ ID for zone B (e.g., use1-az2)."
  type        = string
  default     = "use1-az2"
}

variable "aws_region" {
  description = "AWS region for endpoint service names."
  type        = string
  default     = "us-east-1"
}

variable "endpoints" {
  description = "List of AWS service endpoint names to create (e.g., ['s3', 'ssm', 'ssmmessages'])."
  type        = list(string)
  default     = ["s3", "ssm", "ssmmessages", "ec2messages", "ec2"]
}

# ── Hub account (v1.3.1) ─────────────────────────────────────────────
# The AWS account that OWNS the PHZs (i.e. the account this module runs in).
# Used to decide, per spoke, whether to create a direct same-account
# zone association or a cross-account authorization.
variable "hub_account_id" {
  description = "AWS account ID that owns the centralized endpoint PHZs (the account this module is applied in). Used to split same-account vs cross-account spoke associations."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.hub_account_id))
    error_message = "hub_account_id must be a 12-digit AWS account ID."
  }
}

# ── Spoke associations (v1.3.1: added optional account_id) ───────────
# account_id is OPTIONAL for backward compatibility:
#   • omitted / null → treated as the hub account (same-account path).
#   • set & == hub   → same-account direct zone association.
#   • set & != hub   → cross-account authorization (spoke accepts separately).
variable "spoke_vpc_associations" {
  description = <<-EOT
    List of spoke VPCs to associate with the endpoint PHZs for DNS resolution.

    Each object:
      - vpc_id     (string, required) : the spoke VPC ID
      - region     (string, required) : the spoke VPC region (e.g. "us-east-1")
      - account_id (string, optional) : the spoke VPC's AWS account ID.
                    Omit (or null) for a VPC in the SAME account as the hub PHZs.
                    Set to the spoke's account ID for CROSS-account spokes — the
                    module will create the authorization; the spoke account must
                    then run its own aws_route53_zone_association to accept.
  EOT
  type = list(object({
    vpc_id     = string
    region     = string
    account_id = optional(string)
  }))
  default = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access endpoints (HTTPS/443)."
  type        = list(string)
  default     = ["172.27.0.0/16", "10.0.0.0/8"]
}

# ── Tags ─────────────────────────────────────────────────────────────
variable "aplicacion" { type = string }
variable "propietario_recurso" { type = string }
variable "producto" { type = string }
variable "centro_costo" { type = string }
