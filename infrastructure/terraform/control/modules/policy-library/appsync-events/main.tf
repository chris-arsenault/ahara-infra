variable "prefix" { type = string }
variable "account_id" { type = string }

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "CreateTaggedEventApis"
    actions   = ["appsync:CreateApi"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.prefix]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }
  statement {
    sid       = "ManageProjectEventApis"
    actions   = ["appsync:GetApi", "appsync:UpdateApi", "appsync:DeleteApi", "appsync:ListChannelNamespaces", "appsync:ListTagsForResource", "appsync:TagResource", "appsync:UntagResource"]
    resources = ["arn:aws:appsync:us-east-1:${var.account_id}:apis/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.prefix]
    }
  }
  statement {
    sid = "TagNewEventResources"
    # TagResource also authorizes tag-on-create. This grant can adopt an existing
    # untagged resource; it rejects another Project tag, but is not full isolation.
    # Strict existing-tag conditions require a verified AppSync creation path.
    actions   = ["appsync:TagResource", "appsync:CreateChannelNamespace"]
    resources = ["arn:aws:appsync:us-east-1:${var.account_id}:apis/*", "arn:aws:appsync:us-east-1:${var.account_id}:apis/*/channelNamespace/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.prefix]
    }
    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:ResourceTag/Project"
      values   = [var.prefix]
    }
  }
  statement {
    sid       = "ManageProjectEventNamespaces"
    actions   = ["appsync:GetChannelNamespace", "appsync:UpdateChannelNamespace", "appsync:DeleteChannelNamespace", "appsync:ListTagsForResource", "appsync:TagResource", "appsync:UntagResource"]
    resources = ["arn:aws:appsync:us-east-1:${var.account_id}:apis/*/channelNamespace/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.prefix]
    }
  }
  # AWS does not support resource ARN or tag conditions on these API-key actions.
  # Keep the documented service limitation confined to key management in one region.
  statement {
    sid       = "EventApiKeysInDeploymentRegion"
    actions   = ["appsync:CreateApiKey", "appsync:UpdateApiKey", "appsync:DeleteApiKey", "appsync:ListApiKeys"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }
}

output "policy_json" { value = data.aws_iam_policy_document.this.json }
