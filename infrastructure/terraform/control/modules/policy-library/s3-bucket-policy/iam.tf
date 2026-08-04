# Bucket-policy management for prefix-scoped buckets. Kept separate from
# s3-private-storage because attaching bucket policies is what makes a bucket
# public-readable — grant it only to projects with an approved public bucket
# (e.g. foundry-vtt's game-asset bucket).
data "aws_iam_policy_document" "this" {
  statement {
    sid    = "ManageBucketPolicy"
    effect = "Allow"
    actions = [
      "s3:GetBucketPolicy",
      "s3:GetBucketPolicyStatus",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketOwnershipControls",
      "s3:PutBucketOwnershipControls",
    ]
    resources = ["arn:aws:s3:::${var.prefix}-*"]
  }
}
