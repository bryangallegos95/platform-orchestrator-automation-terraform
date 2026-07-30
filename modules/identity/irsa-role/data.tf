# modules/identity/irsa-role/data.tf
#
# OIDC provider discovery + trust policy construction.
#
# The ROSA HCP module creates a per-cluster OIDC provider in the same AWS
# account. This data source discovers it by URL — no shared state needed.
#
# Trust policy construction uses aws_iam_policy_document for proper JSON
# serialization and multi-SA support (ForAnyValue:StringEquals).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── OIDC provider lookup by URL ───────────────────────────────────────────────
data "aws_iam_openid_connect_provider" "rosa" {
  url = "https://${var.oidc_issuer_url}"
}

# ── Trust policy documents (one per role) ─────────────────────────────────────
# Uses aws_iam_policy_document for:
#   - Proper JSON serialization
#   - Clean handling of single vs multiple :sub conditions
#   - ForAnyValue:StringEquals for multi-SA trust (AWS evaluates as OR)
#
# SECURITY (LOCKED):
#   - StringEquals ONLY (never StringLike — no wildcards allowed)
#   - Audience locked to sts.amazonaws.com
#   - Each SA is an exact match: system:serviceaccount:{ns}:{name}
data "aws_iam_policy_document" "trust" {
  for_each = local.roles

  statement {
    sid     = "AllowOIDCAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # 🔒 LOCKED — Audience must be sts.amazonaws.com
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # 🔒 LOCKED — Exact ServiceAccount match (StringEquals, not StringLike)
    # When multiple SAs are defined, AWS IAM evaluates as OR within the
    # same condition key (any of the listed subjects can assume the role).
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_url}:sub"
      values   = each.value.trust_subjects
    }
  }
}
