# =============================================================================
# Production Environment Configuration
# =============================================================================

aws_region   = "us-east-1"
project_name = "n8n-k8s"
environment  = "prod"
owner        = "platform-team"

# VPC Configuration
vpc_cidr            = "10.2.0.0/16"
public_subnet_cidrs = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# EC2 Configuration - Production grade
master_instance_type = "t3.large"
worker_instance_type = "t3.large"
worker_count         = 3 # HA configuration for production
master_count         = 1
node_volume_size     = 100
node_volume_type     = "gp3"

# SSH Configuration - Highly restrictive for production
admin_ssh_cidr = "203.0.113.0/24" # CHANGE THIS: Replace with your actual office/VPN IP range

# S3 Configuration
state_bucket_name     = "n8n-k8s-tf-state-prod"
artifact_bucket_name  = "n8n-k8s-artifacts-prod"
state_lock_table_name = "n8n-k8s-tf-lock-prod"

# DNS Configuration
domain_name         = "k8s.example.com"
create_route53_zone = false # Assumes zone already exists in production

# SSH Key - SHOULD USE EXISTING KEY IN PRODUCTION
ssh_public_key = ""

# RKE2 Configuration - Stable version
rke2_version = "v1.29"
