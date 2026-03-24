# =============================================================================
# Terraform Variables Configuration Guide
# =============================================================================

## Overview

This Terraform infrastructure uses `.tfvars` files to manage environment-specific configurations. This approach allows you to:

- Keep sensitive values out of version control
- Easily switch between environments (dev/staging/prod)
- Maintain consistent variable naming across environments
- Avoid hardcoded defaults in variable definitions

---

## Available .tfvars Files

### 1. **terraform.tfvars** (Default)
The default variables file used when running Terraform without the `-var-file` flag.

**When to use**: Development/testing environments

```bash
terraform init
terraform plan
terraform apply  # Uses terraform.tfvars
```

### 2. **terraform.dev.tfvars** (Development)
Optimized for development with smaller instance types and minimal worker nodes.

**When to use**: Local development, testing new features

```bash
terraform plan -var-file="terraform.dev.tfvars"
terraform apply -var-file="terraform.dev.tfvars"
```

**Configuration**:
- Master instance: `t3.small`
- Worker nodes: 1
- Volume size: 30 GB
- SSH access: `0.0.0.0/0` (open)

### 3. **terraform.staging.tfvars** (Staging)
Production-like configuration with moderate resources for testing.

**When to use**: Pre-production testing, integration testing

```bash
terraform plan -var-file="terraform.staging.tfvars"
terraform apply -var-file="terraform.staging.tfvars"
```

**Configuration**:
- Master instance: `t3.medium`
- Worker nodes: 2
- Volume size: 50 GB
- SSH access: Restricted to internal network

### 4. **terraform.prod.tfvars** (Production)
High-availability configuration with production-grade security.

**When to use**: Production deployments only

```bash
terraform plan -var-file="terraform.prod.tfvars"
terraform apply -var-file="terraform.prod.tfvars"
```

**Configuration**:
- Master instance: `t3.large`
- Worker nodes: 3
- Volume size: 100 GB
- SSH access: Restricted to specific IP/CIDR (MUST CONFIGURE)

---

## Key Variables Explained

### General
- **aws_region**: AWS region for deployment (e.g., `us-east-1`)
- **project_name**: Project identifier used in resource naming
- **environment**: Environment label (dev/staging/prod)
- **owner**: Team/owner for resource tagging

### VPC/Networking
- **vpc_cidr**: VPC CIDR block (e.g., `10.0.0.0/16`)
- **public_subnet_cidrs**: List of public subnet CIDR blocks
- **availability_zones**: AWS availability zones to use

### EC2 Nodes
- **master_count**: Number of master nodes (default: 1)
- **master_instance_type**: Instance type for master (e.g., `t3.medium`)
- **worker_count**: Number of worker nodes
- **worker_instance_type**: Instance type for workers
- **node_volume_size**: EBS volume size in GB
- **node_volume_type**: EBS volume type (gp3, gp2, etc.)

### Security
- **admin_ssh_cidr**: CIDR block allowed to SSH (IMPORTANT: Restrict in production!)
- **ssh_public_key**: Public SSH key for EC2 access (leave empty for auto-generation)

### S3 State Management
- **state_bucket_name**: S3 bucket for Terraform state
- **artifact_bucket_name**: S3 bucket for cluster artifacts
- **state_lock_table_name**: DynamoDB table for state locking

### Route 53 DNS
- **domain_name**: Public domain name for DNS records
- **create_route53_zone**: Whether to create a new hosted zone

### RKE2 Kubernetes
- **rke2_version**: RKE2 release version (e.g., `v1.29`)

---

## Usage Examples

### Deploy Development Cluster
```bash
cd infra
terraform init
terraform plan -var-file="terraform.dev.tfvars"
terraform apply -var-file="terraform.dev.tfvars"
```

### Deploy Production Cluster
```bash
cd infra

# 1. First, update IMPORTANT variables in terraform.prod.tfvars:
#    - admin_ssh_cidr: Your office/VPN IP range
#    - domain_name: Your actual domain
#    - create_route53_zone: false (if zone already exists)

# 2. Deploy
terraform init
terraform plan -var-file="terraform.prod.tfvars"
terraform apply -var-file="terraform.prod.tfvars"
```

### Switch Between Environments
```bash
# Show what's deployed with staging config
terraform show  # Shows current state

# Plan changes for production
terraform plan -var-file="terraform.prod.tfvars"
```

---

## Important Security Considerations

### Production Deployments ⚠️

1. **SSH Access** (`admin_ssh_cidr`):
   - ❌ DON'T use `0.0.0.0/0` in production
   - ✅ Use your office/VPN IP range (e.g., `203.0.113.0/24`)

2. **Domain Name**:
   - Update to your actual domain
   - Set `create_route53_zone = false` if zone already exists

3. **RKE2 Version**:
   - Pin to a stable version in production
   - Test in staging first before updating

4. **State File** (`terraform.prod.tfvars`):
   - Configure remote state in S3 (see backend.tf)
   - Enable encryption: `encrypt = true` in backend config

5. **SSH Keys**:
   - For production, provide an existing public key
   - Never store private keys in version control

---

## Count Loop Implementation

### Master Nodes
The master node module now supports scaling via the `master_count` variable:

```hcl
# In terraform.prod.tfvars
master_count = 1  # Default: single master

# Or for HA:
master_count = 3  # Creates 3 master nodes (advanced)
```

### Worker Nodes
Worker nodes are controlled via `worker_count`:

```hcl
worker_count = 3  # Scale workers independently
```

Both use count loops internally for cleaner resource management.

---

## Troubleshooting

### "Error: Variable not set"
Make sure you're using the correct tfvars file:
```bash
terraform apply -var-file="terraform.dev.tfvars"
```

### "S3 bucket already exists"
Bucket names must be globally unique. Update the bucket names in your tfvars file.

### "SSH key not found"
For production, ensure your SSH public key is configured:
```hcl
ssh_public_key = "ssh-rsa AAAA... your-key"
```

---

## Best Practices

1. **Always use tfvars files** - Never rely on defaults for production
2. **Version control** - Commit tfvars files WITHOUT sensitive values:
   - ✅ Commit: `terraform.dev.tfvars`, `terraform.staging.tfvars`
   - ❌ Don't commit: `terraform.prod.tfvars`, `.local.tfvars`

3. **Use terraform.local.tfvars** - For local testing/overrides:
   ```bash
   terraform apply -var-file="terraform.dev.tfvars" -var-file="terraform.local.tfvars"
   ```

4. **Review before applying**:
   ```bash
   terraform plan -var-file="terraform.prod.tfvars" > plan.txt
   # Review plan.txt carefully!
   terraform apply plan_file.tfplan
   ```

5. **State management**:
   - Enable remote state in backend.tf for production
   - Enable versioning on state bucket
   - Use DynamoDB table for state locking

---

## Next Steps

1. Update `.tfvars` files with your actual values
2. Review the `backend.tf` configuration for remote state
3. Run `terraform init` to initialize the workspace
4. Run `terraform plan` to verify configuration
5. Run `terraform apply` to create infrastructure

For more information, see the main README.md in the project root.
