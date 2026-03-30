# =============================================================================
# Terraform Variables - Default Configuration
# Environment: Can be overridden with specific environment tfvars files
# =============================================================================

# =============================================================================
# General Configuration
# =============================================================================
aws_region   = "us-east-1"
project_name = "n8n-k8s"
cluster_name = "rke2-cluster"
environment  = "dev"
owner        = "platform-team"

# =============================================================================
# VPC / Networking Configuration
# =============================================================================
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# =============================================================================
# SSH Key Pair Configuration
# =============================================================================
# Leave empty to auto-generate; provide public key material for existing key
ssh_public_key = ""

# =============================================================================
# EC2 Nodes Configuration
# =============================================================================
master_instance_type = "t3.medium"
worker_instance_type = "t3.large"
worker_count         = 3
master_count         = 1
node_volume_size     = 50
node_volume_type     = "gp3"
admin_ssh_cidr       = "0.0.0.0/0" # IMPORTANT: Restrict to your IP in production!

# =============================================================================
# S3 Artifacts Bucket Configuration
# =============================================================================
artifact_bucket_name = "n8n-k8s-artifacts"

# =============================================================================
# Route 53 / DNS Configuration
# =============================================================================
# domain_name         = "example.com"       # Set to your actual domain name
domain_name         = "ahsan.wssolutionsprovider.com"
create_route53_zone = false # Disabled: k8s.example.com is reserved by AWS



# =============================================================================
# RKE2 Configuration
# =============================================================================
rke2_version = "v1.29"
