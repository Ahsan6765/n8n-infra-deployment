# =============================================================================
# Terraform Remote State Backend (S3 + DynamoDB locking)
# =============================================================================
# IMPORTANT: The S3 bucket and DynamoDB table must be created MANUALLY before
# running terraform init. This prevents circular dependencies and ensures
# manual control over state management infrastructure.
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
