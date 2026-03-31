# =============================================================================
# Staging Environment Configuration
# =============================================================================

aws_region   = "us-east-1"
project_name = "n8n-k8s"
environment  = "staging"
owner        = "platform-team"

# VPC Configuration
vpc_cidr            = "10.1.0.0/16"
public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# EC2 Configuration - Medium for staging
master_instance_type = "t3.medium"
worker_instance_type = "t3.medium"
worker_count         = 2 # Moderate scale for staging
master_count         = 1
node_volume_size     = 50
node_volume_type     = "gp3"

# SSH Configuration - More restrictive than dev
admin_ssh_cidr = "10.0.0.0/8" # Internal network only

# S3 Configuration
state_bucket_name     = "n8n-k8s-tf-state-staging"
artifact_bucket_name  = "n8n-k8s-artifacts-staging"
state_lock_table_name = "n8n-k8s-tf-lock-staging"

# DNS Configuration
domain_name         = "ahsan.wssolutionsprovider.com"
create_route53_zone = true

# SSH Key
ssh_public_key = ""

# RKE2 Configuration
rke2_version = "v1.29"
