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

variable "worker_count" {
  description = "Number of worker nodes to create."
  type        = number
  default     = 3
}

variable "subnet_ids" {
  description = "List of subnet IDs to distribute worker nodes across."
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to worker instances."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes."
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
  description = "RKE2 version channel (e.g. v1.29)."
  type        = string
}

variable "master_private_ip" {
  description = "Private IP of the RKE2 master node (agents connect to port 9345)."
  type        = string
}

variable "rke2_token" {
  description = "RKE2 shared cluster secret for agent join."
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region."
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
