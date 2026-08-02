variable "prefix" {
  description = "Project prefix for resource scoping"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "additional_secret_arns" {
  description = "Additional Secrets Manager ARNs owned by the project but outside its standard prefix"
  type        = list(string)
  default     = []
}
