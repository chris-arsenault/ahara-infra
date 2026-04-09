variable "name" {
  description = "Base name used for resource tags."
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name to attach. Leave null to skip."
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Subnet ID for the primary network interface."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups to attach to the network interface."
  type        = list(string)
}

variable "user_data" {
  description = "Rendered user data to bootstrap the instance."
  type        = string
}

variable "associate_eip" {
  description = "Associate a public Elastic IP with the instance."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "Instance type to launch."
  type        = string
  default     = "t3.micro"
}

variable "refresh_cron_expression" {
  description = "EventBridge Scheduler cron expression used to trigger instance refresh."
  type        = string
  default     = "cron(0 8 * * ? *)"
}
