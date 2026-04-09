resource "github_actions_secret" "state_bucket" {
  for_each = var.allowed_repos

  repository      = each.value
  secret_name     = "STATE_BUCKET"
  plaintext_value = module.terraform-state.state_bucket
}

resource "github_actions_secret" "oidc_role" {
  for_each = var.allowed_repos

  repository      = each.value
  secret_name     = "OIDC_ROLE"
  plaintext_value = aws_iam_role.this.arn
}

resource "github_actions_secret" "prefix" {
  for_each = var.allowed_repos

  repository      = each.value
  secret_name     = "PREFIX"
  plaintext_value = var.prefix
}
