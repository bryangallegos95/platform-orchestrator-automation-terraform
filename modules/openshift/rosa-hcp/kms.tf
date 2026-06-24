# modules/openshift/rosa-hcp/kms.tf
#
# Grants the ROSA worker + relevant operator roles permission to USE the EBS
# default-encryption CMK. Required when the account encrypts EBS by default with
# a customer-managed key (workers' root volumes + EBS CSI PVCs are encrypted).
#
# Uses aws_kms_grant (additive) — does NOT manage/overwrite the key policy, so it
# coexists with existing key-policy statements (admins, EKS, ViaService, etc.).
#
# integracion: ebs_kms_key_arn = the SHARED key (same for every cluster).
# negocio:     ebs_kms_key_arn = the cluster's INDIVIDUAL key.
# empty string => no grants (AWS-managed aws/ebs key in use).

locals {
  kms_grantee_role_arns = var.ebs_kms_key_arn == "" ? {} : {
    worker = "arn:aws:iam::${var.aws_account_id}:role/${var.account_role_prefix}-HCP-ROSA-Worker-Role"
    capa   = "arn:aws:iam::${var.aws_account_id}:role/${var.cluster_name}-kube-system-capa-controller-manager"
    ebscsi = "arn:aws:iam::${var.aws_account_id}:role/${var.cluster_name}-openshift-cluster-csi-drivers-ebs-cloud-credentials"
  }
}

resource "aws_kms_grant" "rosa_ebs" {
  for_each = local.kms_grantee_role_arns

  name              = "${var.cluster_name}-rosa-${each.key}"
  key_id            = var.ebs_kms_key_arn
  grantee_principal = each.value

  operations = [
    "Encrypt",
    "Decrypt",
    "ReEncryptFrom",
    "ReEncryptTo",
    "GenerateDataKey",
    "GenerateDataKeyWithoutPlaintext",
    "DescribeKey",
    "CreateGrant",
  ]

  # Operator roles (capa, ebs-csi) are created by module.operator_roles; the
  # worker role by account-bootstrap. Grants must come AFTER those roles exist —
  # this solves the chicken-and-egg automatically (no manual put-key-policy).
  depends_on = [module.operator_roles]
}
