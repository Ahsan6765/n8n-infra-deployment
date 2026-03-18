output "instance_ids" {
  description = "List of EC2 instance IDs for all worker nodes."
  value       = aws_instance.worker[*].id
}

output "public_ips" {
  description = "List of public IP addresses assigned to worker nodes."
  value       = aws_instance.worker[*].public_ip
}

output "private_ips" {
  description = "List of private IP addresses for worker nodes."
  value       = aws_instance.worker[*].private_ip
}
