output "master_sg_id" {
  description = "ID of the master node security group."
  value       = aws_security_group.master.id
}

output "worker_sg_id" {
  description = "ID of the worker node security group."
  value       = aws_security_group.worker.id
}
