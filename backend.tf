# =============================================================================
# Terraform Remote State Backend (S3 + DynamoDB locking)
# =============================================================================
# NOTE: Bootstrap the S3 bucket and DynamoDB table BEFORE enabling this backend.
#       Run:  terraform apply -target=module.s3
#       Then uncomment this block and re-run:  terraform init -migrate-state
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "k8s-cluster-tf-state" # override with var at init time
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "k8s-cluster-tf-lock"
  }
}
