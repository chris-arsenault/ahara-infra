data "aws_iam_policy_document" "this" {
  # ACM certificate ARNs use AWS-generated IDs and cannot be scoped by prefix.
  statement {
    sid    = "AcmCertificates"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DeleteCertificate",
      "acm:DescribeCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:ListTagsForCertificate",
      "acm:ListCertificates",
      "acm:UpdateCertificateOptions"
    ]
    resources = ["*"]
  }

  # Route53 hosted zones use AWS-generated IDs.
  statement {
    sid    = "Route53Records"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
      "route53:GetChange"
    ]
    resources = [
      "arn:aws:route53:::hostedzone/*",
      "arn:aws:route53:::change/*"
    ]
  }
}
