# Terraform State Storage – Manual Setup Guide

## Overview

This infrastructure uses a **manual** approach to manage Terraform state storage. The S3 bucket and DynamoDB table for state locking are created **outside of Terraform** using the AWS Console. This separation of concerns provides better control and prevents circular dependencies.

---

## Prerequisites

- AWS Management Console access
- Appropriate IAM permissions to create S3 buckets and DynamoDB tables

---

## Step-by-Step Setup

### Task 1: Create S3 Bucket for Terraform State

#### 1.1 Log in to AWS Management Console
- Navigate to **S3 Service**

#### 1.2 Create Bucket
1. Click **Create Bucket**
2. Configure the bucket as follows:

| Setting | Value |
|---------|-------|
| **Bucket Name** | `terraform-state-n8n-k8s` |
| **Region** | `us-east-1` (or your deployment region) |
| **ACL** | Private |
| **Block Public Access** | **Enable all** (recommended) |
| **Versioning** | **Enable** (required for state recovery) |
| **Encryption** | **Enable** (SSE-S3) |
| **Tags** | See below |

#### 1.3 Add Tags to S3 Bucket

Apply the following tags for consistency with the infrastructure:

```
Project     = "n8n-k8s"
Environment = "dev"
ManagedBy   = "Manual"
Owner       = "platform-team"
Purpose     = "terraform-state"
```

#### 1.4 Create State Folder Structure

Inside the bucket, create a folder path:

```
terraform-state/
```

This matches the `key` setting in `backend.tf`:

```hcl
key = "terraform-state/terraform.tfstate"
```

---

### Task 2: Create DynamoDB Table for State Locking

#### 2.1 Navigate to DynamoDB
- Go to **DynamoDB Service** in AWS Console
- Click **Create Table**

#### 2.2 Configure DynamoDB Table

| Setting | Value |
|---------|-------|
| **Table Name** | `terraform-state-lock` |
| **Partition Key** | `LockID` (String) |
| **Billing Mode** | **PAY_PER_REQUEST** |
| **Point-in-Time Recovery** | **Enable** (optional but recommended) |

#### 2.3 Add Tags to DynamoDB Table

```
Project     = "n8n-k8s"
Environment = "dev"
ManagedBy   = "Manual"
Owner       = "platform-team"
Purpose     = "terraform-state-lock"
```

---

### Task 3: Verify Backend Configuration

The `backend.tf` file is configured to use the manually created S3 bucket:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-n8n-k8s"
    key            = "terraform-state/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Do NOT modify the bucket or table names** unless you created them with different names. If you did, update `backend.tf` accordingly.

---

## Terraform Initialization After State Setup

Once the S3 bucket and DynamoDB table are created, initialize Terraform:

```bash
cd infra/

# Initialize Terraform with the S3 backend
terraform init

# Validate the configuration
terraform validate

# Preview the infrastructure
terraform plan

# Deploy if plan looks correct
terraform apply
```

### If you had a local state file

If you previously used a local state file, migrate it to the S3 backend:

```bash
terraform init -migrate-state
# When prompted: type 'yes' to confirm migration
```

---

## Verification Checklist

- [ ] S3 bucket created: `terraform-state-n8n-k8s`
- [ ] S3 versioning enabled
- [ ] S3 encryption enabled (SSE-S3)
- [ ] S3 public access blocked
- [ ] Folder created: `terraform-state/` inside bucket
- [ ] DynamoDB table created: `terraform-state-lock`
- [ ] DynamoDB table has `LockID` partition key
- [ ] Both resources tagged with Project/Environment/Owner
- [ ] `backend.tf` contains correct bucket and table names
- [ ] `terraform init` completes successfully
- [ ] `terraform validate` shows no errors

---

## Backup and Recovery

### S3 Versioning
The S3 bucket has versioning enabled. This allows you to recover previous state versions if needed:

```bash
# List all versions of the terraform state file
aws s3api list-object-versions \
  --bucket terraform-state-n8n-k8s \
  --prefix terraform-state/

# Restore a previous version if needed
aws s3api get-object \
  --bucket terraform-state-n8n-k8s \
  --key terraform-state/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup
```

### DynamoDB Point-in-Time Recovery
If enabled, DynamoDB point-in-time recovery allows restoration to any time within 35 days.

---

## Security Best Practices

1. **Enable MFA Delete** (optional, for extra security):
   - Go to S3 bucket settings → Versioning
   - Enable "MFA Delete" (requires MFA to delete versions)

2. **Enable S3 Access Logging** (optional):
   - Configure a separate logging bucket
   - Enable access logs to track all S3 operations

3. **Restrict IAM Permissions**:
   - Only grant S3 and DynamoDB access to authorized team members
   - Use IAM policies to restrict to specific bucket/table

4. **Enable S3 Object Lock** (if immutability required):
   - Consider enabling WORM (Write Once Read Many) mode
   - Prevents accidental or malicious modification

---

## Cleanup (if needed)

**WARNING**: Only do this to completely destroy the infrastructure.

```bash
# Backup the state file first
aws s3 cp \
  s3://terraform-state-n8n-k8s/terraform-state/terraform.tfstate \
  ./terraform.tfstate.backup

# Delete from Terraform
terraform destroy

# Delete the S3 bucket and DynamoDB table manually:
# 1. Go to S3 Console → Select bucket → Delete
# 2. Go to DynamoDB Console → Select table → Delete
```

---

## Troubleshooting

### "Error: s3api: NoSuchBucket"

**Cause**: The S3 bucket doesn't exist or the name is incorrect.

**Solution**:
1. Verify the bucket was created in the correct region
2. Update `backend.tf` if you created the bucket with a different name
3. Run `terraform init -reconfigure` after updating backend.tf

### "Error: AccessDenied"

**Cause**: IAM user/role lacks S3 or DynamoDB permissions.

**Solution**:
1. Verify IAM user has `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` permissions
2. Verify IAM user has DynamoDB `dynamodb:DescribeTable`, `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:UpdateItem`, `dynamodb:DeleteItem` permissions
3. Apply the required IAM policy to your user/role

### "Error: Lock held by..."

**Cause**: Another Terraform operation is running or was interrupted.

**Solution**:
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>

# Replace <LOCK_ID> with the ID shown in the error message
```

---

## Related Files

- [backend.tf](./backend.tf) – Terraform backend configuration
- [variables.tf](./variables.tf) – Terraform variables (no longer includes state bucket variables)
- [modules/s3/main.tf](./modules/s3/main.tf) – Now only creates artifact bucket
- [README.md](./README.md) – General infrastructure documentation

---

## revision

Created: 2024
Last Updated: 2024
