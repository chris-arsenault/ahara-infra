# ── Core Infrastructure ──────────────────────────────────────

module "terraform-state" {
  source           = "../policy-library/terraform-state"
  prefix           = var.prefix
  account_id       = var.account_id
  state_key_prefix = var.state_key_prefix
}

module "control-plane" {
  source     = "../policy-library/control-plane"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── Compute & APIs ───────────────────────────────────────────

module "lambda-deploy" {
  source     = "../policy-library/lambda-deploy"
  prefix     = var.prefix
  account_id = var.account_id
}

module "alb-target-group" {
  source     = "../policy-library/alb-target-group"
  prefix     = var.prefix
  account_id = var.account_id
}

module "alb-loadbalancer" {
  source     = "../policy-library/alb-loadbalancer"
  prefix     = var.prefix
  account_id = var.account_id
}

module "dynamodb" {
  source     = "../policy-library/dynamodb"
  prefix     = var.prefix
  account_id = var.account_id
}

module "bedrock-inference" {
  source     = "../policy-library/bedrock-inference"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── Web Hosting & DNS ────────────────────────────────────────

module "s3-website" {
  source     = "../policy-library/s3-website"
  prefix     = var.prefix
  account_id = var.account_id
}

module "cloudfront-distribution" {
  source     = "../policy-library/cloudfront-distribution"
  prefix     = var.prefix
  account_id = var.account_id
}

module "acm-dns" {
  source     = "../policy-library/acm-dns"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── Identity & Auth ──────────────────────────────────────────

module "cognito-client" {
  source     = "../policy-library/cognito-client"
  prefix     = var.prefix
  account_id = var.account_id
}

module "cognito-pool" {
  source     = "../policy-library/cognito-pool"
  prefix     = var.prefix
  account_id = var.account_id
}

module "cognito-identity-pool" {
  source     = "../policy-library/cognito-identity-pool"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── IAM ──────────────────────────────────────────────────────

module "iam-roles" {
  source     = "../policy-library/iam-roles"
  prefix     = var.prefix
  account_id = var.account_id
}

module "iam-instance-profiles" {
  source     = "../policy-library/iam-instance-profiles"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── Data & Messaging ────────────────────────────────────────

module "db-migrate" {
  source     = "../policy-library/db-migrate"
  prefix     = var.prefix
  account_id = var.account_id
}

module "rds" {
  source     = "../policy-library/rds"
  prefix     = var.prefix
  account_id = var.account_id
}

module "sns" {
  source     = "../policy-library/sns"
  prefix     = var.prefix
  account_id = var.account_id
}

module "ssm-write" {
  source                     = "../policy-library/ssm-write"
  prefix                     = var.prefix
  account_id                 = var.account_id
  additional_parameter_paths = var.ssm_additional_parameter_paths
}

module "secrets-manager" {
  source     = "../policy-library/secrets-manager"
  prefix     = var.prefix
  account_id = var.account_id
}

module "kms-admin" {
  source     = "../policy-library/kms-admin"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── EC2 & Networking ─────────────────────────────────────────

module "ec2-security-groups" {
  source     = "../policy-library/ec2-security-groups"
  prefix     = var.prefix
  account_id = var.account_id
}

module "ec2-vpc-compute" {
  source     = "../policy-library/ec2-vpc-compute"
  prefix     = var.prefix
  account_id = var.account_id
}

module "wafv2" {
  source     = "../policy-library/wafv2"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── TrueNAS / Komodo ────────────────────────────────────────

module "komodo-deploy" {
  source     = "../policy-library/komodo-deploy"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── Account Governance ───────────────────────────────────────

module "budgets-costexplorer" {
  source     = "../policy-library/budgets-costexplorer"
  prefix     = var.prefix
  account_id = var.account_id
}

# ── Policy Map ───────────────────────────────────────────���───

locals {
  policy_map = {
    "terraform-state"         = module.terraform-state.policy_json
    "control-plane"           = module.control-plane.policy_json
    "lambda-deploy"           = module.lambda-deploy.policy_json
    "alb-target-group"        = module.alb-target-group.policy_json
    "alb-loadbalancer"        = module.alb-loadbalancer.policy_json
    "dynamodb"                = module.dynamodb.policy_json
    "bedrock-inference"       = module.bedrock-inference.policy_json
    "s3-website"              = module.s3-website.policy_json
    "cloudfront-distribution" = module.cloudfront-distribution.policy_json
    "acm-dns"                 = module.acm-dns.policy_json
    "cognito-client"          = module.cognito-client.policy_json
    "cognito-pool"            = module.cognito-pool.policy_json
    "cognito-identity-pool"   = module.cognito-identity-pool.policy_json
    "iam-roles"               = module.iam-roles.policy_json
    "iam-instance-profiles"   = module.iam-instance-profiles.policy_json
    "db-migrate"              = module.db-migrate.policy_json
    "rds"                     = module.rds.policy_json
    "sns"                     = module.sns.policy_json
    "ssm-write"               = module.ssm-write.policy_json
    "secrets-manager"         = module.secrets-manager.policy_json
    "kms-admin"               = module.kms-admin.policy_json
    "ec2-security-groups"     = module.ec2-security-groups.policy_json
    "ec2-vpc-compute"         = module.ec2-vpc-compute.policy_json
    "wafv2"                   = module.wafv2.policy_json
    "komodo-deploy"           = module.komodo-deploy.policy_json
    "budgets-costexplorer"    = module.budgets-costexplorer.policy_json
  }
}
