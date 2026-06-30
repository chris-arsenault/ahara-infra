module "project_nas_text_embeddings_inference" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["nas-text-embeddings-inference"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "nas-text-embeddings-inference"
  state_key_prefix = "projects/nas-text-embeddings-inference"

  module_bundles = []

  policy_modules = [
    "komodo-deploy",
  ]
}
