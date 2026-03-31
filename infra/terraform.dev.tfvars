# =============================================================================
# Development Environment Configuration
# =============================================================================

aws_region   = "us-east-1"
project_name = "n8n-k8s"
environment  = "dev"
owner        = "dev-team"

# VPC Configuration
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# EC2 Configuration - Cost optimized for development
master_instance_type = "t3.small"
worker_instance_type = "t3.small"
worker_count         = 1 # Minimal for dev
master_count         = 1
node_volume_size     = 30
node_volume_type     = "gp3"

# SSH Configuration - Development allows broader access
admin_ssh_cidr = "0.0.0.0/0"

# S3 Configuration
state_bucket_name     = "n8n-k8s-tf-state-dev"
artifact_bucket_name  = "n8n-k8s-artifacts-dev"
state_lock_table_name = "n8n-k8s-tf-lock-dev"

# DNS Configuration
domain_name         = "ahsan.wssolutionsprovider.com"
create_route53_zone = true

# SSH Key
ssh_public_key = ""

# RKE2 Configuration
rke2_version = "v1.29"
