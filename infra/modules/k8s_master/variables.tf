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
}

variable "subnet_id" {
  description = "Subnet ID to launch the master instance in."
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to the master instance."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for the master node."
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the EC2 Key Pair for SSH access."
  type        = string
}

variable "iam_instance_profile" {
  description = "Name of the IAM instance profile to attach."
  type        = string
}

variable "volume_size" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 50
}

variable "volume_type" {
  description = "Root EBS volume type."
  type        = string
  default     = "gp3"
}

variable "rke2_version" {
  description = "RKE2 version channel to install (e.g. v1.29)."
  type        = string
  default     = "v1.29"
}

variable "domain_name" {
  description = "Domain name used in RKE2 TLS SANs."
  type        = string
  default     = "k8s.example.com"
}

variable "aws_region" {
  description = "AWS region (used in user-data for SSM calls)."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning."
  type        = string
  default     = ""
}

variable "scripts_dir" {
  description = "Path to the scripts directory containing master.sh and worker.sh."
  type        = string
  default     = "../../scripts"
}
