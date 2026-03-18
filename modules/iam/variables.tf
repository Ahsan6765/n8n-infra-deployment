variable "project_name" {
  description = "Project name prefix for IAM resource names."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}

variable "artifact_bucket_arn" {
  description = "ARN of the artifact S3 bucket to grant node access to."
  type        = string
}
