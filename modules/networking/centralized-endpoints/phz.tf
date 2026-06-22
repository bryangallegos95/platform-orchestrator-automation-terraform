# modules/networking/centralized-endpoints/phz.tf
#
# Route 53 Private Hosted Zones — override public DNS for AWS services.
# Associated with spoke VPCs so they resolve endpoints to private IPs.
#
# ┌─ v1.3.1 ────────────────────────────────────────────────────────────┐
# │ SPOKE ASSOCIATION NOW SPLITS BY ACCOUNT:                             │
# │   • Same account as the hub PHZ  → aws_route53_zone_association      │
# │     (single-step, single-provider — AWS REJECTS an authorization     │
# │      for a VPC in the same account as the zone).                     │
# │   • Different account             → aws_route53_vpc_association_      │
# │     authorization (hub authorizes; the SPOKE account must run the    │
# │     matching aws_route53_zone_association to ACCEPT — that accept     │
# │     step needs spoke-account creds and is therefore OUT OF SCOPE     │
# │     for this hub-side module).                                       │
# │                                                                      │
# │ The split is computed in locals.tf from each entry's account_id      │
# │ compared to var.hub_account_id.                                      │
# └──────────────────────────────────────────────────────────────────────┘

# ── PHZ per service ───────────────────────────────────────────────────
resource "aws_route53_zone" "endpoint" {
  for_each = toset(var.endpoints)

  name    = "${each.key}.${var.aws_region}.amazonaws.com"
  comment = "Centralized VPC Endpoint PHZ for ${each.key} — managed by Terraform"

  vpc {
    vpc_id     = var.vpc_id
    vpc_region = var.aws_region
  }

  tags = merge(local.tags, {
    Name = "phz-aw-${local.region_short}-vpce-${each.key}"
  })

  # PHZ must keep the primary VPC association. We also ignore the full vpc
  # set so that same-account spoke associations created via the separate
  # aws_route53_zone_association resource do not appear as drift on the zone.
  lifecycle {
    ignore_changes = [vpc]
  }
}

# ── A records pointing to endpoint DNS names ──────────────────────────
resource "aws_route53_record" "endpoint" {
  for_each = toset(var.endpoints)

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = "${each.key}.${var.aws_region}.amazonaws.com"
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.this[each.key].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.this[each.key].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}

# Wildcard record for S3 (bucket.s3.us-east-1.amazonaws.com)
resource "aws_route53_record" "s3_wildcard" {
  count = contains(var.endpoints, "s3") ? 1 : 0

  zone_id = aws_route53_zone.endpoint["s3"].zone_id
  name    = "*.s3.${var.aws_region}.amazonaws.com"
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.this["s3"].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.this["s3"].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}

# ── Same-account PHZ VPC Associations ─────────────────────────────────
# Direct, single-step association. Used when the spoke VPC lives in the
# SAME account as the hub PHZ (e.g. integracion-dev in the networking
# account). This is the resource the v1.3.0 module was MISSING.
resource "aws_route53_zone_association" "spoke_same_account" {
  for_each = local.same_account_associations

  zone_id    = aws_route53_zone.endpoint[each.value.endpoint].zone_id
  vpc_id     = each.value.vpc_id
  vpc_region = each.value.region
}

# ── Cross-account PHZ VPC Association Authorizations ───────────────────
# Hub-side AUTHORIZATION only. The spoke account must then run a matching
# aws_route53_zone_association (with its own credentials) to ACCEPT. That
# accept step is intentionally NOT in this module — see the runbook.
resource "aws_route53_vpc_association_authorization" "spoke_cross_account" {
  for_each = local.cross_account_associations

  zone_id    = aws_route53_zone.endpoint[each.value.endpoint].zone_id
  vpc_id     = each.value.vpc_id
  vpc_region = each.value.region
}
