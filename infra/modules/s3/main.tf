# =============================================================================
# S3 Module – Artifact Bucket Only
# =============================================================================
# NOTE: The Terraform state bucket and DynamoDB lock table are created manually
#       outside of Terraform. This provides better separation of concerns and
#       prevents circular dependencies.
#
# Manual state infrastructure should be set up using the AWS Console:
# - S3 bucket: terraform-state-<project-name>
# - DynamoDB table: terraform-state-lock
# =============================================================================

# ---- Random suffix to ensure globally unique bucket names ----
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ---- Artifact Bucket ----
resource "aws_s3_bucket" "artifact" {
  bucket        = "${var.artifact_bucket_name}-${random_id.bucket_suffix.hex}"
  force_destroy = false

  tags = {
    Name    = "${var.artifact_bucket_name}-${random_id.bucket_suffix.hex}"
    Purpose = "cluster-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "artifact" {
  bucket = aws_s3_bucket.artifact.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket                  = aws_s3_bucket.artifact.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
