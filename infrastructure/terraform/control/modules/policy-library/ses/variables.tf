variable "prefix" {
  description = "Project prefix for resource scoping"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "additional_ses_identity_domains" {
  description = "Exact SES identity domains this project may manage in addition to the prefix-scoped namespace."
  type        = set(string)
  default     = []
}
