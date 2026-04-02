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

# ---- Master node(s) ----
output "master_public_ips" {
  description = "List of Elastic IP addresses of the Kubernetes master nodes."
  value       = [for master in module.k8s_master : master.public_ip]
}

output "master_private_ips" {
  description = "List of private IPs of the master nodes (used by workers to join)."
  value       = [for master in module.k8s_master : master.private_ip]
}

output "master_instance_ids" {
  description = "List of EC2 instance IDs of the master node(s)."
  value       = [for master in module.k8s_master : master.instance_id]
}

# For backward compatibility, expose first master if it exists
output "master_public_ip" {
  description = "Elastic IP address of the first Kubernetes master node (for backward compatibility)."
  value       = length(module.k8s_master) > 0 ? module.k8s_master[0].public_ip : null
}

output "master_private_ip" {
  description = "Private IP of the first master node (for backward compatibility)."
  value       = length(module.k8s_master) > 0 ? module.k8s_master[0].private_ip : null
}

output "master_instance_id" {
  description = "EC2 instance ID of the first master node (for backward compatibility)."
  value       = length(module.k8s_master) > 0 ? module.k8s_master[0].instance_id : null
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

output "worker_private_ips" {
  description = "List of private IP addresses for the worker nodes (used for inter-cluster communication)."
  value       = module.k8s_workers.private_ips
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

# # ---- S3 ----
# output "artifact_bucket_name" {
#   description = "Name of the cluster artifacts S3 bucket."
#   value       = module.s3.artifact_bucket_name
# }

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
output "ssh_master_commands" {
  description = "SSH commands to connect to the master node(s)."
  value = [
    for idx, master in module.k8s_master :
    "ssh -i cluster-key.pem ubuntu@${master.public_ip}"
  ]
}

output "ssh_worker_commands" {
  description = "SSH commands to connect to the worker node(s)."
  value = [
    for idx, worker_ip in module.k8s_workers.public_ips :
    "ssh -i cluster-key.pem ubuntu@${worker_ip}"
  ]
}

# For backward compatibility
output "ssh_master_command" {
  description = "Ready-to-use SSH command to connect to the first master node."
  value       = length(module.k8s_master) > 0 ? "ssh -i cluster-key.pem ubuntu@${module.k8s_master[0].public_ip}" : null
}

# ---- Automated Cluster Setup ----
output "cluster_setup_status" {
  description = "Status of the automated RKE2 cluster setup. Check this after terraform apply completes."
  value       = length(module.k8s_master) > 0 ? "CLUSTER_SETUP_COMPLETE" : "NO_CLUSTER"
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file retrieved from master node (created during terraform apply)."
  value       = length(module.k8s_master) > 0 ? module.k8s_master[0].kubeconfig_path : null
}

output "kubectl_access" {
  description = "How to access the cluster with kubectl after terraform apply completes."
  value       = length(module.k8s_master) > 0 ? "export KUBECONFIG=${path.root}/kubeconfig-${var.environment}.yaml" : null
}

output "cluster_verification_command" {
  description = "Command to verify cluster is ready after terraform apply completes."
  value       = length(module.k8s_master) > 0 ? "export KUBECONFIG=${path.root}/kubeconfig-${var.environment}.yaml && kubectl get nodes" : null
}
