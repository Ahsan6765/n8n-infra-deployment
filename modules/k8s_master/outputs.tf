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
  description = "RKE2 cluster join token (read from SSM after bootstrap)."
  value       = data.aws_ssm_parameter.rke2_token.value
  sensitive   = true
}
