# Policy that lets the deployment role:
# - manage IAM roles whose name begins with var.role_name_prefix
# - manage this exact deployment role (for drift fixes), but not delete it
data "aws_iam_policy_document" "this" {
  statement {
    sid    = "AllAccountStateManagment"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:ListBucket",
      "s3:PutBucketVersioning",
      "s3:PutBucketTagging",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:Get*",
    ]
    resources = [
      "arn:aws:s3:::tf-state-*",
    ]
  }

  statement {
    sid    = "ManagePrefixedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
      "iam:GetRole",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole"
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/deployer-*",
      "arn:aws:iam::${var.account_id}:role/*/deployer-*"
    ]
  }

  statement {
    sid    = "ManageOIDCProvider"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyDeleteSelf"
    effect    = "Deny"
    actions   = ["iam:DeleteRole"]
    resources = ["arn:aws:iam::${var.account_id}:role/${local.deployment_role_name}"]
  }

  statement {
    sid    = "ReadPlatformControlSSM"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      "arn:aws:ssm:*:${var.account_id}:parameter/ahara/control/*",
    ]
  }

  statement {
    sid    = "AllowPolicyUpdates"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:TagPolicy",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:DeletePolicy"
    ]
    resources = [local.permissions_boundary_arn]
  }

  statement {
    sid    = "ManageRolesAnywhere"
    effect = "Allow"
    actions = [
      "rolesanywhere:CreateProfile",
      "rolesanywhere:UpdateProfile",
      "rolesanywhere:DeleteProfile",
      "rolesanywhere:GetProfile",
      "rolesanywhere:ListProfiles",
      "rolesanywhere:EnableProfile",
      "rolesanywhere:DisableProfile",
      "rolesanywhere:CreateTrustAnchor",
      "rolesanywhere:UpdateTrustAnchor",
      "rolesanywhere:DeleteTrustAnchor",
      "rolesanywhere:GetTrustAnchor",
      "rolesanywhere:ListTrustAnchors",
      "rolesanywhere:EnableTrustAnchor",
      "rolesanywhere:DisableTrustAnchor",
      "rolesanywhere:TagResource",
      "rolesanywhere:UntagResource",
      "rolesanywhere:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManagePrivateCA"
    effect = "Allow"
    actions = [
      "acm-pca:CreateCertificateAuthority",
      "acm-pca:DeleteCertificateAuthority",
      "acm-pca:RestoreCertificateAuthority",
      "acm-pca:UpdateCertificateAuthority",
      "acm-pca:DescribeCertificateAuthority",
      "acm-pca:GetCertificateAuthorityCertificate",
      "acm-pca:GetCertificateAuthorityCsr",
      "acm-pca:ImportCertificateAuthorityCertificate",
      "acm-pca:IssueCertificate",
      "acm-pca:GetCertificate",
      "acm-pca:ListCertificateAuthorities",
      "acm-pca:ListTags",
      "acm-pca:TagCertificateAuthority",
      "acm-pca:UntagCertificateAuthority",
    ]
    resources = ["*"]
  }
}
