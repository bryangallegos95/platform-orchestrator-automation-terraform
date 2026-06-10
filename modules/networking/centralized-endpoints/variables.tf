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

variable "spoke_vpc_associations" {
  description = "List of spoke VPC IDs to associate with PHZs for DNS resolution."
  type = list(object({
    vpc_id = string
    region = string
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
