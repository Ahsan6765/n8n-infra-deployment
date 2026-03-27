output "instance_id" {
  description = "EC2 instance ID of the master node."
  value       = aws_instance.master.id
}

output "public_ip" {
  description = "Elastic IP (public IP) of the master node."
  value       = aws_eip.master.public_ip
}

output "private_ip" {
  description = "Private IP address of the master node."
  value       = aws_instance.master.private_ip
}

output "rke2_token" {
  description = "RKE2 cluster join token retrieved from master node."
  value       = try(file("${path.root}/rke2-token-${var.environment}.txt"), "")
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file retrieved from master node."
  value       = "${path.root}/kubeconfig-${var.environment}.yaml"
}

output "token_retrieval_status" {
  description = "Debug output showing if token file was successfully retrieved."
  value       = fileexists("${path.root}/rke2-token-${var.environment}.txt") ? "[SUCCESS] Token file exists" : "[FAILED] Token file MISSING - token retrieval failed"
  sensitive   = false
}

output "kubeconfig_retrieval_status" {
  description = "Debug output showing if kubeconfig was successfully retrieved."
  value       = fileexists("${path.root}/kubeconfig-${var.environment}.yaml") ? "[SUCCESS] Kubeconfig file exists" : "[FAILED] Kubeconfig file MISSING - retrieval failed"
  sensitive   = false
}
