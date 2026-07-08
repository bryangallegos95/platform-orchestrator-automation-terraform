# Palo Alto VM-Series with GWLB + Auto Scaling Group Deployment

Reusable Terraform module that deploys Palo Alto Networks VM-Series Next-Generation
Firewalls behind an AWS Gateway Load Balancer (GWLB) with Auto Scaling for centralized
traffic inspection.

Supports both **active (PROD)** and **warm standby (DR)** modes from the same module,
controlled via input variables.

---

## Architecture Overview

```
                      Strata Cloud Manager (SaaS, Global)
                      Device Group: shared policies
                               |
            ┌──────────────────┴──────────────────────┐
            |                                          |
   us-east-1 (PROD)                          us-east-2 (DR)
   ASG: min=2, des=2, max=4                  ASG: min=0, des=0, max=4
   Warm Pool: none                           Warm Pool: 2x Stopped
   Licenses: 2 active                       Licenses: 0 (stopped)
```

### Single-Region Topology (PROD or DR)

```
┌─────────────────────────────────────────────────────────────────────────┐
|  INSPECTION VPC                                                          |
|                                                                          |
|  ┌──────────────────────────────────────────────────────────────────┐   |
|  | TGW Subnets (existing)                                            |   |
|  | RT: 0.0.0.0/0 -> GWLBe-PA  (switchover from NFW during migration)|   |
|  └──────────────────────┬───────────────────────────────────────────┘   |
|                          | traffic from spokes                           |
|                          v                                               |
|  ┌──────────────────────────────────────────────────────────────────┐   |
|  | GWLBe-PA Subnets (CREATED BY THIS MODULE)                         |   |
|  | 172.27.65.0/28 (az1) + 172.27.65.16/28 (az2)                     |   |
|  | VPC Endpoints -> GWLB                                             |   |
|  | RT: 0.0.0.0/0 -> TGW (return path after inspection)              |   |
|  └──────────────────────┬───────────────────────────────────────────┘   |
|                          | GENEVE (UDP 6081)                             |
|                          v                                               |
|  ┌──────────────────────────────────────────────────────────────────┐   |
|  | Data-Plane Subnets (EXISTING - shared with AWS NFW)               |   |
|  | 172.27.64.64/26 (az1) + 172.27.64.128/26 (az2)                   |   |
|  |                                                                    |   |
|  | Contains:                                                          |   |
|  |   - GWLB (created by this module)                                 |   |
|  |   - PA VM eth0 ENIs (data-plane, source_dest_check=false)         |   |
|  |   - AWS NFW ENIs (coexist during migration)                       |   |
|  |                                                                    |   |
|  | RT: NO additional routes needed (GENEVE is bump-in-the-wire)      |   |
|  └──────────────────────────────────────────────────────────────────┘   |
|                                                                          |
|  ┌──────────────────────────────────────────────────────────────────┐   |
|  | Management Subnets (CREATED BY THIS MODULE)                       |   |
|  | 172.27.65.32/28 (az1) + 172.27.65.48/28 (az2)                    |   |
|  |                                                                    |   |
|  | Contains: PA VM eth1 ENIs (mgmt, attached by Lambda post-launch)  |   |
|  | RT: 0.0.0.0/0 -> TGW -> Egress VPC -> NAT -> Internet -> SCM     |   |
|  └──────────────────────────────────────────────────────────────────┘   |
|                                                                          |
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Key Design Decisions

### mgmt-interface-swap = enable

The PA VM-Series uses `mgmt-interface-swap` in the bootstrap config:
- **eth0** becomes the **data-plane** interface (receives GENEVE from GWLB)
- **eth1** becomes the **management** interface (SCM, licensing, updates)

This is required because:
1. GWLB can only send traffic to the primary ENI (eth0)
2. ASG Launch Templates only support one ENI at launch time
3. The Lambda lifecycle hook attaches eth1 (mgmt) post-launch

### Data-plane is bump-in-the-wire

The GWLB encapsulates traffic in GENEVE and sends it to eth0. The firewall
inspects the packet and returns it on the **same interface** back to the GWLB.
No L3 routing is required on the data-plane subnet. This is why the existing
FW subnets work without any route table modifications.

### Dedicated GWLBe subnets (not shared with NFW)

The GWLB endpoints for Palo Alto have their own subnets with independent route
tables. This enables:
- Independent routing (NFW return path vs PA return path)
- Canary migration (TGW subnet route points to either NFW or PA GWLBe)
- Clean rollback (change one route, instant revert)

### Management egress path

```
PA eth1 -> Mgmt Subnet RT (0/0 -> TGW) -> TGW rt-inspection (0/0 -> egress)
  -> Egress VPC -> NAT GW -> IGW -> Internet -> Strata Cloud Manager
```

This path already exists in the hub networking architecture. No modifications
to the Egress VPC or TGW routing are required for management connectivity.

---

## DR Strategy: Warm Pool (Active-Passive)

### Why Warm Pool over Pilot Light

| Criteria | Pilot Light | Warm Pool (chosen) |
|----------|-------------|-------------------|
| Monthly cost | ~$88 | ~$108 (+$20) |
| RTO | 10-15 min | **3-5 min** |
| Bootstrap risk | High (cold start) | **Low** (pre-bootstrapped) |
| License cost while idle | $0 | **$0** |
| Failover reliability | Medium | **High** |

### How it works

```
NORMAL STATE (DR):
  ASG: desired=0, min=0, max=4
  Warm Pool: 2 instances in "Stopped" state
    - Already bootstrapped (PAN-OS on EBS)
    - Already have mgmt ENI attached
    - Licenses NOT consumed (stopped = inactive in SCM)
    - Cost: EBS storage only (~$19/month for 2x60GB gp3)

FAILOVER (DR activated):
  1. ASG desired_capacity set to 2 (manual or automated)
  2. Warm pool instances transition: Stopped -> Running (~90s)
  3. PAN-OS boots from EBS (already has bootstrap config)
  4. Connects to SCM, activates license from credit pool
  5. GWLB health checks pass (~3-5 min total)
  6. Traffic flows through PA in DR region
```

### Licensing during DR

With **Software NGFW Credits** (flexible licensing):
- Credits are consumed per-hour only when a firewall is **active and connected**
- Stopped instances in warm pool consume **zero credits**
- The credit pool is **global** - covers both regions
- You only need enough credits for max simultaneous capacity
- Example: 2 (prod) + 2 (DR during failover) = 4 credits max

### Cross-Region considerations

| Resource | Cross-region? | DR approach |
|----------|--------------|-------------|
| TGW | Regional only | Separate TGW in us-east-2 |
| GWLB | Regional only | This module creates one per region |
| VPC/Subnets | Regional only | This module creates them |
| S3 Bootstrap | Regional | Use S3 CRR from prod bucket |
| AMI | Regional | Use Marketplace AMI for us-east-2 |
| SCM Policies | Global (SaaS) | Same Device Group, auto-sync |
| License pool | Global | Same credit pool, no extra cost |

### Failover trigger options

1. **Manual:** GitHub Actions workflow_dispatch -> Lambda -> ASG update
2. **Automated:** Route53 health check -> CloudWatch Alarm -> EventBridge -> Lambda
3. **Semi-auto:** CloudWatch alarm pages on-call -> operator confirms -> workflow

### Bootstrap bucket replication

```
us-east-1                              us-east-2
┌──────────────────────┐    CRR     ┌──────────────────────┐
| s3-bootstrap-prod    | ---------> | s3-bootstrap-dr      |
| /config/init-cfg.txt |            | /config/init-cfg.txt |
| /license/authcodes   |            | /license/authcodes   |
| /content/            |            | /content/            |
└──────────────────────┘            └──────────────────────┘
```

Set up CRR externally. The DR layer references the replica bucket via
`create_bootstrap_bucket = false` + `bootstrap_bucket_name`.

---

## Migration Strategy (AWS NFW -> Palo Alto)

This module coexists with the existing AWS Network Firewall during migration:

```
Phase 1: Deploy PA (no traffic)
  - PA running, registered in SCM, policies committed
  - TGW subnets still route to NFW GWLBe (no change)

Phase 2: Canary migration
  - TGW subnet RT: specific CIDRs -> GWLBe-PA
  - Remaining traffic -> NFW GWLBe (unchanged)
  - Rollback: remove the specific routes (< 60s)

Phase 3: Full cutover
  - TGW subnet RT: 0.0.0.0/0 -> GWLBe-PA
  - NFW in pass-through / monitor mode

Phase 4: Decommission NFW
  - Remove NFW resources (separate PR, CODEOWNERS review)
```

The key enabler is **dedicated GWLBe subnets** with independent route tables.
During migration, the TGW subnet route table is the only thing that changes.

---

## Usage

### PROD deployment

```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/networking/palo-alto-vmseries?ref=v2.0.0"
}

inputs = {
  name_prefix = "pa-aw-ue1-inspection"
  ambiente    = "prod"
  aws_region  = "us-east-1"

  vpc_id          = dependency.foundation.outputs.inspection_vpc_id
  tgw_id          = dependency.foundation.outputs.tgw_id
  data_subnet_ids = dependency.foundation.outputs.inspection_fw_subnet_ids

  gwlbe_subnet_cidrs = [
    { cidr = "172.27.65.0/28",  az = "use1-az1" },
    { cidr = "172.27.65.16/28", az = "use1-az2" }
  ]
  mgmt_subnet_cidrs = [
    { cidr = "172.27.65.32/28", az = "use1-az1" },
    { cidr = "172.27.65.48/28", az = "use1-az2" }
  ]

  ami_id           = "ami-XXXXXXXXX" # PA-VM 11.1.x from Marketplace
  instance_type    = "m5.2xlarge"
  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  bootstrap_options = {
    mgmt_interface_swap         = "enable"
    plugin_op_commands          = "panorama-licensing-mode-on,aws-gwlb-inspect:enable,aws-gwlb-overlay-routing:enable"
    panorama_server             = ""
    auth_key                    = "XXXXXXXX"
    dgname                      = "DG-HUB-INSPECTION"
    tplname                     = "TS-HUB-VM300"
    dhcp_send_hostname          = "yes"
    dhcp_send_client_id         = "yes"
    dhcp_accept_server_hostname = "yes"
    dhcp_accept_server_domain   = "yes"
  }
}
```

### DR deployment (Warm Pool)

```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/networking/palo-alto-vmseries?ref=v2.0.0"
}

inputs = {
  name_prefix = "pa-aw-ue2-inspection"
  ambiente    = "dr"
  aws_region  = "us-east-2"

  vpc_id          = dependency.foundation_dr.outputs.inspection_vpc_id
  tgw_id          = dependency.foundation_dr.outputs.tgw_id
  data_subnet_ids = dependency.foundation_dr.outputs.inspection_fw_subnet_ids

  gwlbe_subnet_cidrs = [
    { cidr = "10.X.X.0/28",  az = "use2-az1" },
    { cidr = "10.X.X.16/28", az = "use2-az2" }
  ]
  mgmt_subnet_cidrs = [
    { cidr = "10.X.X.32/28", az = "use2-az1" },
    { cidr = "10.X.X.48/28", az = "use2-az2" }
  ]

  ami_id           = "ami-YYYYYYYYY" # PA-VM 11.1.x for us-east-2
  min_size         = 0
  desired_capacity = 0
  max_size         = 4

  warm_pool_config = {
    enabled                     = true
    pool_state                  = "Stopped"
    min_size                    = 2
    max_group_prepared_capacity = 4
    reuse_on_scale_in           = true
  }

  create_bootstrap_bucket = false
  bootstrap_bucket_name   = "s3-aw-ue2-paloalto-bootstrap-dr"

  bootstrap_options = {
    mgmt_interface_swap         = "enable"
    plugin_op_commands          = "panorama-licensing-mode-on,aws-gwlb-inspect:enable,aws-gwlb-overlay-routing:enable"
    panorama_server             = ""
    auth_key                    = "XXXXXXXX"
    dgname                      = "DG-HUB-INSPECTION"
    tplname                     = "TS-HUB-VM300"
    dhcp_send_hostname          = "yes"
    dhcp_send_client_id         = "yes"
    dhcp_accept_server_hostname = "yes"
    dhcp_accept_server_domain   = "yes"
  }
}
```

---

## Prerequisites

1. **Inspection VPC** with existing FW subnets (data-plane)
2. **Transit Gateway** with `appliance_mode_support = enable` on the Inspection VPC attachment
3. **Egress VPC** with NAT Gateways (for management internet access)
4. **TGW route table** `rt-inspection` with `0.0.0.0/0 -> egress` (already exists)
5. **Strata Cloud Manager** tenant with:
   - Device Group configured
   - Template Stack with virtual router, interfaces, zones
   - Security policies (allow-all for testing, then production rules)
   - Interface Management Profile enabling HTTPS (for GWLB health checks)
6. **S3 bootstrap bucket** with `config/init-cfg.txt` and `license/authcodes`
7. **PA-VM AMI** from AWS Marketplace (per-region)

---

## Resources Created

| Resource | Count | Purpose |
|----------|-------|---------|
| `aws_subnet` | 4 | GWLBe (2) + Mgmt (2) |
| `aws_route_table` + associations + routes | 4 | Return-to-TGW routing |
| `aws_lb` (GWLB) | 1 | Traffic distribution |
| `aws_lb_target_group` | 1 | ASG registration |
| `aws_lb_listener` | 1 | GENEVE listener |
| `aws_vpc_endpoint_service` | 1 | Expose GWLB |
| `aws_vpc_endpoint` (GWLBe) | 2 | One per AZ |
| `aws_launch_template` | 1 | VM-Series config |
| `aws_autoscaling_group` | 1 | Scale in/out |
| `aws_autoscaling_group_warm_pool` | 0-1 | DR only |
| `aws_autoscaling_lifecycle_hook` | 2 | Launch + Terminate |
| `aws_security_group` | 2 | Data + Mgmt |
| `aws_iam_role` + policies | 2 | VM + Lambda |
| `aws_lambda_function` | 1 | ENI management |
| `aws_cloudwatch_event_rule` + target | 1 | Lifecycle trigger |
| `aws_cloudwatch_log_group` | 3 | Traffic/Threat/System |
| `aws_cloudwatch_metric_alarm` | 1 | Unhealthy targets |
| `aws_s3_bucket` + config | 0-1 | Bootstrap (optional) |
| **Total** | **~28-30** | |

---

## Outputs

| Output | Description | Used by |
|--------|-------------|---------|
| `gwlbe_ids` | GWLB Endpoint IDs per AZ | Routing layer (TGW subnet RT) |
| `asg_name` | ASG name | DR failover automation |
| `bootstrap_bucket_name` | S3 bucket for bootstrap | CRR configuration |
| `vpce_service_name` | Endpoint Service name | Cross-account sharing |

---

## Cost Estimate

### PROD (us-east-1, 2 active instances)

| Component | Monthly cost |
|-----------|-------------|
| 2x m5.2xlarge (On-Demand) | ~$760 |
| GWLB (hourly + processing) | ~$50 |
| 2x 60GB gp3 EBS | ~$19 |
| NAT GW data (mgmt traffic only) | ~$5 |
| CloudWatch Logs | ~$10 |
| Software NGFW Credits (2 units) | Per agreement |
| **Total (excl. licenses)** | **~$844/month** |

### DR (us-east-2, Warm Pool)

| Component | Monthly cost |
|-----------|-------------|
| GWLB (hourly, no data) | ~$20 |
| 2x 60GB gp3 EBS (stopped) | ~$19 |
| NAT GW (pre-provisioned) | ~$65 |
| S3 bootstrap replica | ~$3 |
| Lambda (minimal) | ~$1 |
| Software NGFW Credits | $0 (stopped) |
| **Total** | **~$108/month** |

---

## References

- [VM-Series Integration with AWS GWLB](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/set-up-the-vm-series-firewall-on-aws/vm-series-integration-with-gateway-load-balancer)
- [VM-Series ASG with GWLB](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/set-up-the-vm-series-firewall-on-aws/vm-series-integration-with-gateway-load-balancer/vm-series-auto-scaling-group-with-gateway-load-balancer)
- [Palo Alto Terraform Reference Architecture](https://developers.paloaltonetworks.com/terraform/docs/swfw/aws/vmseries/reference-architectures/combined_design_autoscale/)
- [AWS Warm Pools Documentation](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html)
- [Strata Cloud Manager](https://docs.paloaltonetworks.com/strata-cloud-manager)
- [Software NGFW Credits Licensing](https://docs.paloaltonetworks.com/vm-series/11-0/vm-series-deployment/license-the-vm-series-firewall/software-ngfw)
