variable "prefix" {
  description = "Project prefix used for role names and SSM registration paths."
  type        = string
}

variable "name" {
  description = "Short workload use-case name, for example backup or lambda-invoker."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase kebab-case."
  }
}

variable "policy_json" {
  description = "Runtime IAM policy JSON for the workload role."
  type        = string
}

variable "role_name" {
  description = "Optional explicit role name. Defaults to <prefix>-truenas-<name>."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for the workload role."
  type        = map(string)
  default     = {}
}
