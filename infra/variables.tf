# =============================================================================
# General
# =============================================================================
variable "aws_region" {
  description = "AWS region where all resources will be deployed."
  type        = string
}

variable "project_name" {
  description = "Short project name used as a name prefix for all resources."
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name (used for cluster ownership tags)."
  type        = string
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, staging, production)."
  type        = string
}

variable "owner" {
  description = "Owner / team tag applied to all resources."
  type        = string
}

# =============================================================================
# VPC / Networking
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ, min 3)."
  type        = list(string)
}

variable "availability_zones" {
  description = "List of Availability Zones to spread subnets across."
  type        = list(string)
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
}

variable "worker_instance_type" {
  description = "EC2 instance type for Kubernetes worker nodes."
  type        = string
}

variable "master_count" {
  description = "Number of Kubernetes master nodes to create (typically 1)."
  type        = number
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes to create."
  type        = number
}

variable "node_volume_size" {
  description = "Root EBS volume size in GB for each node."
  type        = number
}

variable "node_volume_type" {
  description = "EBS volume type for node root disks."
  type        = string
}

variable "admin_ssh_cidr" {
  description = "CIDR block allowed to SSH into cluster nodes. Restrict to your IP in production."
  type        = string
}

# =============================================================================
# S3 Artifacts Bucket
# =============================================================================
variable "artifact_bucket_name" {
  description = "Globally unique name for the cluster artifacts S3 bucket."
  type        = string
}

# =============================================================================
# Route 53
# =============================================================================
variable "domain_name" {
  description = "Public Route 53 hosted zone domain name (e.g. example.com)."
  type        = string
}

variable "create_route53_zone" {
  description = "Whether to create a new Route 53 hosted zone (false = use existing)."
  type        = bool
}

# =============================================================================
# RKE2
# =============================================================================
variable "rke2_version" {
  description = "RKE2 release channel or version tag to install (e.g. v1.29)."
  type        = string
}
