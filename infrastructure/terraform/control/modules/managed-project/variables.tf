variable "prefix" {
  description = "Name prefix for all resources managed by this project"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  type        = string
}

variable "allowed_repos" {
  description = "List of GitHub repos (owner/repo) allowed to assume this role"
  type        = set(string)
}

variable "allowed_branches" {
  description = "Allowed branch globs (e.g., main, release/*)"
  type        = set(string)
}

variable "allow_pull_request" {
  description = "Allow GitHub Actions OIDC tokens issued for pull_request events."
  type        = bool
  default     = false
}

variable "policy_modules" {
  description = "Individual policy primitives to attach to the deployer role (for things outside the ahara-tf-patterns shared modules)"
  type        = set(string)
  default     = []
}

variable "module_bundles" {
  description = "ahara-tf-patterns modules this project uses. Auto-expands to the set of policy primitives each module needs. Valid values: 'website', 'alb-api', 'cognito-app', 'lambda'."
  type        = set(string)
  default     = []
}

variable "state_key_prefix" {
  description = "S3 key prefix for this project's state files (e.g. ahara, projects/svap)"
  type        = string
}

variable "ssm_additional_parameter_paths" {
  description = "Additional SSM parameter path prefixes this project can write to (for ssm-write module)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the role"
  type        = map(string)
  default     = {}
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "github_pat" {
  type        = string
  description = "Github PAT for writing github secrets"
}
