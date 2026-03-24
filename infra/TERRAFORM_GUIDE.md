# Terraform Configuration Guide

## Overview

This Terraform infrastructure code uses environment-specific variable files (tfvars) to manage different configurations for dev, staging, and production environments.

## File Structure

```
infra/
├── terraform.tfvars              # Default/fallback configuration
├── terraform.tfvars.example      # Example configuration (committed to repo)
├── terraform.dev.tfvars          # Development environment (NOT in git)
├── terraform.staging.tfvars      # Staging environment (NOT in git)
├── terraform.prod.tfvars         # Production environment (NOT in git)
├── .gitignore                    # Prevents committing sensitive files
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── modules/
    ├── vpc/
    ├── iam/
    ├── security_groups/
    ├── key_pair/
    ├── k8s_master/
    ├── k8s_worker/
    ├── route53/
    └── s3/
```

## Setup Instructions

### Step 1: Start from the Example File

```bash
cd infra/
cp terraform.tfvars.example terraform.tfvars
```

### Step 2: Customize for Your Environment

Edit `terraform.tfvars` with your deployment values:

```bash
vi terraform.tfvars
```

### Step 3: Create Environment-Specific Files (Optional but Recommended)

For managing multiple environments:

```bash
# Development
cp terraform.tfvars terraform.dev.tfvars
# Edit and customize for dev

# Staging
cp terraform.tfvars terraform.staging.tfvars
# Edit and customize for staging

# Production
cp terraform.tfvars terraform.prod.tfvars
# Edit and customize for production
```

## Key Variables

### General Configuration
- `aws_region` - AWS region for deployment (default: us-east-1)
- `project_name` - Project name prefix (default: n8n-k8s)
- `environment` - Environment label: dev, staging, prod
- `owner` - Owner/team tag (default: platform-team)

### VPC / Networking
- `vpc_cidr` - VPC CIDR block (default: 10.0.0.0/16)
- `public_subnet_cidrs` - Public subnet CIDRs (default: 3 subnets)
- `availability_zones` - AZs to spread resources (default: 3 AZs in us-east-1)

### EC2 Nodes
- `master_instance_type` - Master node instance type (default: t3.medium)
- `worker_instance_type` - Worker node instance type (default: t3.medium)
- `master_count` - Number of master nodes (default: 1, use count loop)
- `worker_count` - Number of worker nodes (default: 3)
- `node_volume_size` - Root volume size in GB (default: 50)
- `node_volume_type` - Root volume type (default: gp3)
- `admin_ssh_cidr` - CIDR allowed to SSH (⚠️ restrict in production!)

### Storage
- `state_bucket_name` - S3 bucket for Terraform state
- `artifact_bucket_name` - S3 bucket for cluster artifacts
- `state_lock_table_name` - DynamoDB table for state locking

### DNS
- `domain_name` - Route 53 hosted zone domain
- `create_route53_zone` - Create new zone (true) or use existing (false)

### RKE2
- `rke2_version` - RKE2 version channel (default: v1.29)

### SSH Access
- `ssh_public_key` - Your SSH public key (leave empty for auto-generation)

## Usage Examples

### Apply with Default Values
```bash
terraform init
terraform plan
terraform apply
```

### Apply with Specific Environment File
```bash
terraform init
terraform plan -var-file="terraform.dev.tfvars"
terraform apply -var-file="terraform.dev.tfvars"
```

### Using Different Environments with Workspaces (Advanced)
```bash
# Create workspace
terraform workspace new dev
terraform workspace select dev
terraform init
terraform apply -var-file="terraform.dev.tfvars"

# Create another workspace
terraform workspace new prod
terraform workspace select prod
terraform init
terraform apply -var-file="terraform.prod.tfvars"
```

## Important Security Notes

### ⚠️ SENSITIVE VALUES
The following should NEVER be committed to version control:
- `terraform.*.tfvars` files (except example)
- `.tfstate` files
- Private SSH keys (*.pem)
- Kubeconfig files

These are automatically ignored by `.gitignore`.

### 🔐 Production Security

Before applying to production, ensure:

1. **Restrict SSH Access**
   ```hcl
   admin_ssh_cidr = "203.0.113.42/32"  # Your IP only
   ```

2. **Use Appropriate Instance Types**
   ```hcl
   master_instance_type = "t3.medium"    # For small clusters
   master_instance_type = "t3.large"     # For production
   ```

3. **Enable Encryption**
   - S3 encryption: ✅ Enabled by default
   - EBS encryption: ✅ Enabled by default
   - State encryption: ✅ Enabled by default

4. **Use Scaling**
   ```hcl
   worker_count = 5  # More workers for production
   ```

5. **Use Strong Domain**
   ```hcl
   domain_name = "your-domain.com"
   create_route53_zone = false  # Use existing zone
   ```

## Common Tasks

### Scale Worker Nodes
Edit `terraform.dev.tfvars`:
```hcl
worker_count = 5  # From 3 to 5
```

Then apply:
```bash
terraform apply -var-file="terraform.dev.tfvars"
```

### Change Instance Types
Edit the tfvars file and reapply:
```hcl
worker_instance_type = "t3.large"
```

### Update RKE2 Version
```hcl
rke2_version = "v1.30"
```

### Add Multiple Master Nodes (HA)
```hcl
master_count = 3
```

## Outputs

After `terraform apply`, retrieve outputs:

```bash
# Get all outputs
terraform output

# Get specific output
terraform output master_public_ip
terraform output worker_instance_ids
terraform output ssh_master_command

# Save outputs as JSON
terraform output -json > outputs.json
```

## Troubleshooting

### Variable not recognized
Ensure the variable is defined in `variables.tf` and exists in your tfvars file.

### State file conflicts
Do NOT edit `.tfstate` files manually. Use `terraform state` commands.

### SSH key permissions
If using auto-generated key:
```bash
chmod 600 cluster-key.pem
ssh -i cluster-key.pem ubuntu@<master-public-ip>
```

### Terraform validation
```bash
terraform fmt -recursive .    # Format files
terraform validate           # Validate syntax
terraform plan              # Plan changes
```

## Cleanup

To destroy all resources:

```bash
# With default variables
terraform destroy

# With specific environment
terraform destroy -var-file="terraform.dev.tfvars"

# Auto-approve (careful!)
terraform destroy -auto-approve -var-file="terraform.dev.tfvars"
```

## References

- [Terraform Variables Documentation](https://www.terraform.io/language/values/variables)
- [Terraform Variable Files](https://www.terraform.io/language/values/variables#variable-definitions-tfvars-files)
- [RKE2 Documentation](https://docs.rke2.io/)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues or questions:
1. Run `terraform plan` to see what would change
2. Check `terraform.tfvars` for correct values
3. Verify AWS credentials are configured
4. Review `.gitignore` to ensure sensitive files aren't exposed
