# =============================================================================
# Root Main – Orchestrates all modules
# =============================================================================

# -----------------------------------------------------------------------------
# Auto-generate SSH key pair if the user didn't supply a public key
# -----------------------------------------------------------------------------
resource "tls_private_key" "cluster" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  content         = tls_private_key.cluster[0].private_key_pem
  filename        = "${path.root}/cluster-key.pem"
  file_permission = "0600"
}

locals {
  effective_public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.cluster[0].public_key_openssh
}

# -----------------------------------------------------------------------------
# S3 – Remote state bucket + artifact bucket
# -----------------------------------------------------------------------------
module "s3" {
  source = "./modules/s3"

  state_bucket_name    = var.state_bucket_name
  artifact_bucket_name = var.artifact_bucket_name
  lock_table_name      = var.state_lock_table_name
  project_name         = var.project_name
  environment          = var.environment
}

# -----------------------------------------------------------------------------
# IAM – Instance roles and profiles for EC2 nodes
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  project_name        = var.project_name
  environment         = var.environment
  artifact_bucket_arn = module.s3.artifact_bucket_arn
}

# -----------------------------------------------------------------------------
# Key Pair – SSH access to nodes
# -----------------------------------------------------------------------------
module "key_pair" {
  source = "./modules/key_pair"

  key_name   = "${var.project_name}-${var.environment}-key"
  public_key = local.effective_public_key
}

# -----------------------------------------------------------------------------
# VPC – Networking foundation
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
}

# -----------------------------------------------------------------------------
# Security Groups – Access rules for master and worker nodes
# -----------------------------------------------------------------------------
module "security_groups" {
  source = "./modules/security_groups"

  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.vpc.vpc_id
  admin_ssh_cidr = var.admin_ssh_cidr
}

# -----------------------------------------------------------------------------
# K8s Master Node (1 instance)
# -----------------------------------------------------------------------------
module "k8s_master" {
  source = "./modules/k8s_master"

  project_name         = var.project_name
  environment          = var.environment
  subnet_id            = module.vpc.public_subnet_ids[0]
  security_group_ids   = [module.security_groups.master_sg_id]
  instance_type        = var.master_instance_type
  key_name             = module.key_pair.key_name
  iam_instance_profile = module.iam.instance_profile_name
  volume_size          = var.node_volume_size
  volume_type          = var.node_volume_type
  rke2_version         = var.rke2_version
  aws_region           = var.aws_region
}

# -----------------------------------------------------------------------------
# K8s Worker Nodes (3 instances)
# -----------------------------------------------------------------------------
module "k8s_workers" {
  source = "./modules/k8s_worker"

  project_name         = var.project_name
  environment          = var.environment
  worker_count         = var.worker_count
  subnet_ids           = module.vpc.public_subnet_ids
  security_group_ids   = [module.security_groups.worker_sg_id]
  instance_type        = var.worker_instance_type
  key_name             = module.key_pair.key_name
  iam_instance_profile = module.iam.instance_profile_name
  volume_size          = var.node_volume_size
  volume_type          = var.node_volume_type
  rke2_version         = var.rke2_version
  master_private_ip    = module.k8s_master.private_ip
  rke2_token           = module.k8s_master.rke2_token
  aws_region           = var.aws_region
}

# -----------------------------------------------------------------------------
# Route 53 – DNS management
# -----------------------------------------------------------------------------
module "route53" {
  source = "./modules/route53"

  domain_name      = var.domain_name
  create_zone      = var.create_route53_zone
  master_public_ip = module.k8s_master.public_ip
  project_name     = var.project_name
  environment      = var.environment
}
