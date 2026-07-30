# modules/identity/irsa-role/main.tf
#
# IAM Roles for Service Accounts (IRSA) — ROSA HCP → AWS services.
# One module call = N roles (map-driven). Each role is scoped to specific
# Kubernetes ServiceAccounts via OIDC trust policy.
#
# What this module creates (per role):
#   1. IAM role with OIDC trust policy (scoped to exact ServiceAccount(s))
#   2. Inline IAM policies (defined by the son repo)
#   3. Managed policy attachments (defined by the son repo)
#
# What this module does NOT create:
#   - OIDC provider       -> modules/openshift/rosa-hcp (already exists)
#   - Kubernetes SA       -> ArgoCD / Helm charts (K8s side)
#   - KMS keys            -> account baseline
#   - SQS/Redis/Aurora    -> other modules (this module grants access TO them)
#
# Hardening baked in (not configurable off):
#   - Trust: StringEquals (exact SA match, never StringLike wildcards)
#   - Audience: sts.amazonaws.com (prevents token reuse from other IdPs)
#   - Max session: 3600s ceiling (short-lived credentials only)
#   - IAM path: /irsa/ (audit + policy scoping)

# ── IAM Roles ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "this" {
  for_each = local.roles

  name        = each.value.role_name
  path        = local.iam_path
  description = each.value.description

  max_session_duration = each.value.max_session_duration

  # Permission boundary (optional — son repo can restrict further)
  permissions_boundary = (
    each.value.permission_boundary_arn != ""
    ? each.value.permission_boundary_arn
    : null
  )

  # Trust policy constructed via templatefile-like logic in locals
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json

  tags = merge(local.tags, {
    Name        = each.value.role_name
    RoleContext = each.key
  })

  depends_on = [terraform_data.guards]
}

# ── Inline Policies ───────────────────────────────────────────────────────────
resource "aws_iam_role_policy" "inline" {
  for_each = {
    for item in flatten([
      for role_key, role in local.roles : [
        for policy_name, policy_json in role.inline_policies : {
          key         = "${role_key}:${policy_name}"
          role_key    = role_key
          policy_name = policy_name
          policy_json = policy_json
        }
      ]
    ]) : item.key => item
  }

  name   = each.value.policy_name
  role   = aws_iam_role.this[each.value.role_key].id
  policy = each.value.policy_json
}

# ── Managed Policy Attachments ────────────────────────────────────────────────
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = {
    for item in flatten([
      for role_key, role in local.roles : [
        for idx, arn in role.managed_policy_arns : {
          key      = "${role_key}:${idx}"
          role_key = role_key
          arn      = arn
        }
      ]
    ]) : item.key => item
  }

  role       = aws_iam_role.this[each.value.role_key].id
  policy_arn = each.value.arn
}
