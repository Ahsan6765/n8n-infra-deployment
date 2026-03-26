# =============================================================================
# Terraform Remote State Backend (S3 + DynamoDB locking)
# =============================================================================
# IMPORTANT: The S3 bucket and DynamoDB table must be created MANUALLY before
# running terraform init. This prevents circular dependencies and ensures
# manual control over state management infrastructure.
#
# Manual Setup Steps:
# 1. Create S3 bucket: terraform-state-<project-name>
#    - Enable versioning
#    - Enable server-side encryption (SSE-S3)
#    - Block all public access
#
# 2. Create DynamoDB table: terraform-state-lock
#    - Partition Key: LockID (String)
#    - Billing: PAY_PER_REQUEST
#
# 3. Update bucket and table names below with actual names
# 4. Run: terraform init -migrate-state
# =============================================================================
terraform {
  backend "s3" {
    bucket         = "terraform-state-n8n-k8s"
    key            = "terraform-state/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
