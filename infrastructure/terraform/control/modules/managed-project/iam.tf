locals {

  allowed_repos = [for r in var.allowed_repos : "chris-arsenault/${r}"]
  branch_subs = flatten([
    for r in local.allowed_repos : [
      for b in var.allowed_branches : "repo:${r}:ref:refs/heads/${b}"
    ]
  ])
  pull_request_subs = flatten([
    for r in local.allowed_repos : var.allow_pull_request ? ["repo:${r}:pull_request"] : []
  ])
  # Build allowed 'sub' claims for refs, envs, and optionally PR runs:
  # - repo:OWNER/REPO:ref:refs/heads/<branch>
  # - repo:OWNER/REPO:environment:<env>
  # - repo:OWNER/REPO:pull_request
  allowed_subs = concat(
    local.branch_subs,
    local.pull_request_subs
  )
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = length(local.allowed_subs) > 0 ? local.allowed_subs : ["repo:UNKNOWN/*"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "deployer-${var.prefix}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.tags
  path               = "/${var.prefix}/"
}

# Combine every effective policy module's statements into a single flat list,
# then chunk them into managed policies that fit under the 6144-char per-policy
# limit. Inline policies are capped at 10,240 chars TOTAL per role, which we
# blow past easily with 20+ policy modules attached. Managed policies escape
# that aggregate limit — each counts independently (default quota: 10 per role,
# adjustable to 20).
locals {
  # Parse the JSON string output of each policy module and flatten the Statement arrays.
  all_statements = flatten([
    for module_name in local.effective_policy_modules :
    jsondecode(local.policy_map[module_name]).Statement
  ])

  # Statements per chunk. Empirically ~12 statements stays under 6144 bytes
  # even with beefy resource lists. Lower if a chunk ever overflows.
  statements_per_chunk = 12

  statement_chunks = [
    for i in range(ceil(length(local.all_statements) / local.statements_per_chunk)) :
    slice(
      local.all_statements,
      i * local.statements_per_chunk,
      min((i + 1) * local.statements_per_chunk, length(local.all_statements))
    )
  ]
}

resource "aws_iam_policy" "bundles" {
  count = length(local.statement_chunks)
  name  = "deployer-${var.prefix}-${count.index}"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.statement_chunks[count.index]
  })
}

resource "aws_iam_role_policy_attachment" "bundles" {
  count      = length(local.statement_chunks)
  role       = aws_iam_role.this.id
  policy_arn = aws_iam_policy.bundles[count.index].arn
}

resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.this.id
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}