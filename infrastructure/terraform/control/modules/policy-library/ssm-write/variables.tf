variable "prefix" {
  description = "Project prefix for resource scoping"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "additional_parameter_paths" {
  description = "Additional SSM parameter path prefixes this project can write to"
  type        = list(string)
  default     = []
}
