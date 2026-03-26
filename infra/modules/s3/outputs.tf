output "artifact_bucket_name" {
  description = "The actual name of the artifact S3 bucket."
  value       = aws_s3_bucket.artifact.id
}

output "artifact_bucket_arn" {
  description = "ARN of the artifact S3 bucket."
  value       = aws_s3_bucket.artifact.arn
}

