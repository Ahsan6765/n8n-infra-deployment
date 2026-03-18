variable "state_bucket_name" {
  description = "Base name for the Terraform state S3 bucket (a random suffix will be appended)."
  type        = string
}

variable "artifact_bucket_name" {
  description = "Base name for the cluster artifacts S3 bucket (a random suffix will be appended)."
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
}

variable "project_name" {
  description = "Project name prefix."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}
