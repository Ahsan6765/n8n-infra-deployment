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

output "kubeconfig_path" {
  description = "Path to the kubeconfig file retrieved from master node."
  value       = "${path.root}/kubeconfig-${var.environment}.yaml"
}
