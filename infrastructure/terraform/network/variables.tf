variable "security_log_bucket_name" {
  description = "S3 bucket name for shared security and edge logs"
  type        = string
}

variable "security_log_bucket_arn" {
  description = "S3 bucket ARN for shared security and edge logs"
  type        = string
}

variable "security_log_bucket_domain_name" {
  description = "S3 bucket domain name for CloudFront standard logs"
  type        = string
}

variable "security_log_bucket_policy_id" {
  description = "Security log bucket policy id; used only to order log-delivery resources after bucket policy creation"
  type        = string
}
