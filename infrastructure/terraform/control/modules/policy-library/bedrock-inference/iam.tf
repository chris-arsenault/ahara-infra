data "aws_iam_policy_document" "this" {
  statement {
    sid    = "BedrockInferenceProfiles"
    effect = "Allow"
    actions = [
      "bedrock:GetInferenceProfile",
      "bedrock:CreateInferenceProfile",
      "bedrock:DeleteInferenceProfile",
      "bedrock:TagResource",
      "bedrock:ListTagsForResource",
      "bedrock:UntagResource"
    ]
    resources = ["*"]
  }
}
