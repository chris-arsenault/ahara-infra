data "aws_iam_policy_document" "this" {
  # File-system creation cannot be ARN-scoped; require the Project tag at
  # creation and scope all management to it afterwards.
  statement {
    sid       = "CreateFileSystem"
    effect    = "Allow"
    actions   = ["elasticfilesystem:CreateFileSystem", "elasticfilesystem:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/Project"
      values   = [var.prefix]
    }
  }

  statement {
    sid    = "ManageFileSystem"
    effect = "Allow"
    actions = [
      "elasticfilesystem:DeleteFileSystem",
      "elasticfilesystem:UpdateFileSystem",
      "elasticfilesystem:CreateMountTarget",
      "elasticfilesystem:DeleteMountTarget",
      "elasticfilesystem:PutLifecycleConfiguration",
      "elasticfilesystem:PutBackupPolicy",
      "elasticfilesystem:PutFileSystemPolicy",
      "elasticfilesystem:DeleteFileSystemPolicy",
      "elasticfilesystem:TagResource",
      "elasticfilesystem:UntagResource",
    ]
    resources = ["arn:aws:elasticfilesystem:*:${var.account_id}:file-system/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.prefix]
    }
  }

  # Describe calls do not support resource-level scoping or tags.
  statement {
    sid    = "DescribeFileSystems"
    effect = "Allow"
    actions = [
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:DescribeMountTargetSecurityGroups",
      "elasticfilesystem:DescribeLifecycleConfiguration",
      "elasticfilesystem:DescribeBackupPolicy",
      "elasticfilesystem:DescribeFileSystemPolicy",
      "elasticfilesystem:DescribeTags",
      "elasticfilesystem:ListTagsForResource",
    ]
    resources = ["*"]
  }
}
