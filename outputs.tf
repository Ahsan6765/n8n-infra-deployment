# =============================================================================
# Root Outputs
# =============================================================================

# ---- VPC ----
output "vpc_id" {
  description = "VPC identifier."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

# ---- Master node ----
output "master_public_ip" {
  description = "Elastic IP address of the Kubernetes master node."
  value       = module.k8s_master.public_ip
}

output "master_private_ip" {
  description = "Private IP of the master node (used by workers to join)."
  value       = module.k8s_master.private_ip
}

output "master_instance_id" {
  description = "EC2 instance ID of the master node."
  value       = module.k8s_master.instance_id
}

# ---- Worker nodes ----
output "worker_instance_ids" {
  description = "List of EC2 instance IDs for the worker nodes."
  value       = module.k8s_workers.instance_ids
}

output "worker_public_ips" {
  description = "List of public IP addresses for the worker nodes."
  value       = module.k8s_workers.public_ips
}

# ---- Key Pair ----
output "key_pair_name" {
  description = "Name of the EC2 key pair created for SSH access."
  value       = module.key_pair.key_name
}

output "private_key_pem_path" {
  description = "Local path to the auto-generated private key (only set when no ssh_public_key was provided)."
  value       = var.ssh_public_key == "" ? local_sensitive_file.private_key[0].filename : "N/A – user-supplied key"
  sensitive   = true
}

# ---- S3 ----
output "state_bucket_name" {
  description = "Name of the Terraform state S3 bucket."
  value       = module.s3.state_bucket_name
}

output "artifact_bucket_name" {
  description = "Name of the cluster artifacts S3 bucket."
  value       = module.s3.artifact_bucket_name
}

# ---- IAM ----
output "node_iam_role_arn" {
  description = "ARN of the IAM role attached to all cluster nodes."
  value       = module.iam.role_arn
}

# ---- Route 53 ----
output "kubernetes_api_dns" {
  description = "DNS name for the Kubernetes API endpoint."
  value       = module.route53.api_dns_name
}

output "wildcard_dns" {
  description = "Wildcard DNS for services (*.k8s.<domain>)."
  value       = module.route53.wildcard_dns_name
}

# ---- SSH command ----
output "ssh_master_command" {
  description = "Ready-to-use SSH command to connect to the master node."
  value       = "ssh -i cluster-key.pem ubuntu@${module.k8s_master.public_ip}"
}
