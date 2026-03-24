# =============================================================================
# General
# =============================================================================
variable "aws_region" {
  description = "AWS region where all resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used as a name prefix for all resources."
  type        = string
  default     = "k8s-cluster"
}

variable "environment" {
  description = "Deployment environment label (e.g. production, staging)."
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Owner / team tag applied to all resources."
  type        = string
  default     = "platform-team"
}

# =============================================================================
# VPC / Networking
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ, min 3)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "availability_zones" {
  description = "List of Availability Zones to spread subnets across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# =============================================================================
# SSH Key Pair
# =============================================================================
variable "ssh_public_key" {
  description = "SSH public key material to install on EC2 nodes. Leave empty to auto-generate a key pair via Terraform."
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# EC2 Nodes
# =============================================================================
variable "master_instance_type" {
  description = "EC2 instance type for the Kubernetes master node."
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for Kubernetes worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "master_count" {
  description = "Number of Kubernetes master nodes to create (typically 1)."
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes to create."
  type        = number
  default     = 3
}

variable "node_volume_size" {
  description = "Root EBS volume size in GB for each node."
  type        = number
  default     = 50
}

variable "node_volume_type" {
  description = "EBS volume type for node root disks."
  type        = string
  default     = "gp3"
}

variable "admin_ssh_cidr" {
  description = "CIDR block allowed to SSH into cluster nodes (restrict to your IP)."
  type        = string
  default     = "0.0.0.0/0" # tighten in production
}

# =============================================================================
# S3 State + Artifacts
# =============================================================================
variable "state_bucket_name" {
  description = "Globally unique name for the Terraform remote-state S3 bucket."
  type        = string
  default     = "k8s-cluster-tf-state"
}

variable "artifact_bucket_name" {
  description = "Globally unique name for the cluster artifacts S3 bucket."
  type        = string
  default     = "k8s-cluster-artifacts"
}

variable "state_lock_table_name" {
  description = "DynamoDB table name used for Terraform state locking."
  type        = string
  default     = "k8s-cluster-tf-lock"
}

# =============================================================================
# Route 53
# =============================================================================
variable "domain_name" {
  description = "Public Route 53 hosted zone domain name (e.g. example.com)."
  type        = string
  default     = "k8s.example.com"
}

variable "create_route53_zone" {
  description = "Whether to create a new Route 53 hosted zone (false = use existing)."
  type        = bool
  default     = true
}

# =============================================================================
# RKE2
# =============================================================================
variable "rke2_version" {
  description = "RKE2 release channel or version tag to install (e.g. v1.29 or latest)."
  type        = string
  default     = "v1.29"
}
