# modules/networking/palo-alto-vmseries/variables.tf
#
# Variables for Palo Alto VM-Series with GWLB + ASG deployment.
# Supports both PROD (active) and DR (warm pool) modes.

# ─── Identity & Region ────────────────────────────────────────────────────────

variable "name_prefix" {
  description = "Prefix for all resource names (e.g. pa-aw-ue1-inspection)"
  type        = string
}

variable "ambiente" {
  description = "Environment tier: dev, qa, preprod, prod, dr"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "preprod", "prod", "dr"], var.ambiente)
    error_message = "ambiente must be one of: dev, qa, preprod, prod, dr"
  }
}

variable "aws_region" {
  description = "AWS region for deployment (us-east-1 for prod, us-east-2 for DR)"
  type        = string
}

# ─── Networking (existing infrastructure) ─────────────────────────────────────

variable "vpc_id" {
  description = "ID of the Inspection VPC where Palo Alto will be deployed"
  type        = string
}

variable "tgw_id" {
  description = "Transit Gateway ID (used for route tables pointing return traffic to TGW)"
  type        = string
}

variable "data_subnet_ids" {
  description = "Existing Firewall subnet IDs (one per AZ) where GWLB and PA data-plane ENIs will reside"
  type        = list(string)
  validation {
    condition     = length(var.data_subnet_ids) == 2
    error_message = "Exactly 2 data subnet IDs required (one per AZ)"
  }
}

# ─── New Subnets (created by this module) ─────────────────────────────────────

variable "gwlbe_subnet_cidrs" {
  description = "CIDR blocks for new GWLB endpoint subnets (one per AZ). These subnets host the VPC Endpoints that receive traffic from TGW subnets."
  type = list(object({
    cidr = string
    az   = string # e.g. "use1-az1", "use1-az2"
  }))
  validation {
    condition     = length(var.gwlbe_subnet_cidrs) == 2
    error_message = "Exactly 2 GWLB endpoint subnet CIDRs required (one per AZ)"
  }
}

variable "mgmt_subnet_cidrs" {
  description = "CIDR blocks for new management subnets (one per AZ). PA management ENIs (eth1) reside here."
  type = list(object({
    cidr = string
    az   = string # e.g. "use1-az1", "use1-az2"
  }))
  validation {
    condition     = length(var.mgmt_subnet_cidrs) == 2
    error_message = "Exactly 2 management subnet CIDRs required (one per AZ)"
  }
}

# ─── Auto Scaling Group ───────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type for VM-Series (VM-300 recommended: m5.2xlarge)"
  type        = string
  default     = "m5.2xlarge"
}

variable "ami_id" {
  description = "AMI ID for Palo Alto VM-Series (region-specific, from AWS Marketplace)"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH access to PA instances (emergency use only)"
  type        = string
  default     = ""
}

variable "min_size" {
  description = "ASG minimum size (prod: 2, dr: 0)"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "ASG desired capacity (prod: 2, dr: 0)"
  type        = number
  default     = 2
}

variable "health_check_grace_period" {
  description = "Seconds before ASG checks health of new instance (PA bootstrap takes ~5-8 min)"
  type        = number
  default     = 600
}

# ─── Warm Pool (DR mode) ──────────────────────────────────────────────────────

variable "warm_pool_config" {
  description = "Warm pool configuration for DR. Instances are pre-bootstrapped and kept Stopped."
  type = object({
    enabled                     = bool
    pool_state                  = string # "Stopped" | "Running" | "Hibernated"
    min_size                    = number
    max_group_prepared_capacity = number
    reuse_on_scale_in           = bool
  })
  default = {
    enabled                     = false
    pool_state                  = "Stopped"
    min_size                    = 0
    max_group_prepared_capacity = 0
    reuse_on_scale_in           = true
  }
}

# ─── Bootstrap ────────────────────────────────────────────────────────────────

variable "bootstrap_options" {
  description = "Palo Alto bootstrap options passed via user-data. Keys map to init-cfg parameters."
  type = object({
    mgmt_interface_swap         = string # "enable"
    plugin_op_commands          = string # "panorama-licensing-mode-on,aws-gwlb-inspect:enable,aws-gwlb-overlay-routing:enable"
    panorama_server             = string # SCM endpoint (or empty if using device certificate)
    auth_key                    = string # Panorama/SCM auth key
    dgname                      = string # Device Group name in SCM
    tplname                     = string # Template Stack name in SCM
    dhcp_send_hostname          = string # "yes"
    dhcp_send_client_id         = string # "yes"
    dhcp_accept_server_hostname = string # "yes"
    dhcp_accept_server_domain   = string # "yes"
  })
}

variable "bootstrap_bucket_name" {
  description = "S3 bucket name for bootstrap files (init-cfg.txt, authcodes, content). Created externally or by this module."
  type        = string
  default     = ""
}

variable "create_bootstrap_bucket" {
  description = "Whether this module should create the S3 bootstrap bucket"
  type        = bool
  default     = true
}

# ─── GWLB ─────────────────────────────────────────────────────────────────────

variable "gwlb_health_check" {
  description = "GWLB target group health check configuration"
  type = object({
    port                = number
    protocol            = string # "HTTPS" or "TCP"
    healthy_threshold   = number
    unhealthy_threshold = number
    interval            = number
  })
  default = {
    port                = 443
    protocol            = "HTTPS"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }
}

variable "cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing on GWLB"
  type        = bool
  default     = true
}

variable "deregistration_delay" {
  description = "Seconds to wait before deregistering targets from GWLB"
  type        = number
  default     = 300
}

# ─── Scaling ──────────────────────────────────────────────────────────────────

variable "scaling_config" {
  description = "Auto scaling plan configuration using PA custom CloudWatch metrics"
  type = object({
    enabled                   = bool
    metric_name               = string # e.g. "panSessionActive", "DataPlaneCPUUtilizationPct"
    target_value              = number
    statistic                 = string # "Average", "Maximum"
    estimated_instance_warmup = number
    cloudwatch_namespace      = string
  })
  default = {
    enabled                   = true
    metric_name               = "panSessionActive"
    target_value              = 75
    statistic                 = "Average"
    estimated_instance_warmup = 900
    cloudwatch_namespace      = "PaloAltoNetworks"
  }
}

# ─── Security Groups ──────────────────────────────────────────────────────────

variable "mgmt_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the management interface (for SCM outbound, health checks)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "data_plane_cidr" {
  description = "VPC CIDR or supernet for the data-plane security group (GENEVE from GWLB)"
  type        = string
  default     = "172.27.64.0/23"
}

# ─── CloudWatch ───────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}

# ─── Delicensing (scale-in) ───────────────────────────────────────────────────

variable "delicense_config" {
  description = "Configuration for automatic delicensing on scale-in events via Lambda"
  type = object({
    enabled        = bool
    ssm_param_name = string # SSM SecureString with SCM credentials for delicensing
  })
  default = {
    enabled        = false
    ssm_param_name = ""
  }
}

# ─── Tags ─────────────────────────────────────────────────────────────────────

variable "aplicacion" {
  description = "Mandatory CloudOps tag: Aplicacion"
  type        = string
}

variable "propietario_recurso" {
  description = "Mandatory CloudOps tag: PropietarioRecurso"
  type        = string
}

variable "producto" {
  description = "Mandatory CloudOps tag: Producto"
  type        = string
}

variable "centro_costo" {
  description = "Mandatory CloudOps tag: CentroCosto"
  type        = string
}

variable "extra_tags" {
  description = "Additional tags to merge with all resources"
  type        = map(string)
  default     = {}
}
