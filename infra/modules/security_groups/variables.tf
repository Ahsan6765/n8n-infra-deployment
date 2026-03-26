variable "project_name" {
  description = "Project name prefix."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name for cluster ownership tags."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "ID of the VPC where security groups will be created."
  type        = string
}

variable "admin_ssh_cidr" {
  description = "CIDR block allowed to SSH into cluster nodes."
  type        = string
  default     = "0.0.0.0/0"
}
