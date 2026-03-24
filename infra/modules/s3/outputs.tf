output "state_bucket_name" {
  description = "The actual name of the Terraform state S3 bucket."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket."
  value       = aws_s3_bucket.state.arn
}

output "artifact_bucket_name" {
  description = "The actual name of the artifact S3 bucket."
  value       = aws_s3_bucket.artifact.id
}

output "artifact_bucket_arn" {
  description = "ARN of the artifact S3 bucket."
  value       = aws_s3_bucket.artifact.arn
}

output "lock_table_name" {
  description = "The DynamoDB lock table name."
  value       = aws_dynamodb_table.lock.name
}
