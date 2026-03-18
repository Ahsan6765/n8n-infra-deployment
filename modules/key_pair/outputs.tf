output "key_name" {
  description = "Name of the EC2 Key Pair."
  value       = aws_key_pair.cluster.key_name
}

output "key_pair_id" {
  description = "ID of the EC2 Key Pair."
  value       = aws_key_pair.cluster.id
}
