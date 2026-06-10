# modules/networking/centralized-endpoints/phz.tf
#
# Route 53 Private Hosted Zones — override public DNS for AWS services.
# Associated with spoke VPCs so they resolve endpoints to private IPs.

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

  # PHZ must keep the primary VPC association
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

# ── Cross-account PHZ VPC Associations ────────────────────────────────
# Associates PHZs with spoke VPCs so their DNS resolves to private endpoints.
# Requires: spoke VPC owner to accept (handled via AWS Organizations).

resource "aws_route53_vpc_association_authorization" "spoke" {
  for_each = {
    for pair in setproduct(var.endpoints, var.spoke_vpc_associations) :
    "${pair[0]}-${pair[1].vpc_id}" => {
      endpoint = pair[0]
      vpc_id   = pair[1].vpc_id
      region   = pair[1].region
    }
  }

  zone_id = aws_route53_zone.endpoint[each.value.endpoint].zone_id
  vpc_id  = each.value.vpc_id

  vpc_region = each.value.region
}
