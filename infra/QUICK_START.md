# 🚀 QUICK START GUIDE - N8N Kubernetes Infrastructure

## 📁 Your New .tfvars Files

```
infra/
├── terraform.tfvars              # ← Dev (default)
├── terraform.dev.tfvars          # ← Development config
├── terraform.staging.tfvars      # ← Staging config  
├── terraform.prod.tfvars         # ← Production config ⚠️
└── TFVARS_GUIDE.md              # ← Full documentation
```

---

## ⚡ Quick Commands

### Deploy to Development
```bash
cd infra
terraform init
terraform plan -var-file="terraform.dev.tfvars"
terraform apply -var-file="terraform.dev.tfvars"
```

### Deploy to Staging
```bash
terraform plan -var-file="terraform.staging.tfvars"
terraform apply -var-file="terraform.staging.tfvars"
```

### Deploy to Production ⚠️ 
```bash
# ⚠️ FIRST: Edit terraform.prod.tfvars and set:
# 1. admin_ssh_cidr = "YOUR.IP.RANGE/32"
# 2. domain_name = "your-domain.com"
# 3. create_route53_zone = false (if using existing zone)

terraform plan -var-file="terraform.prod.tfvars"
terraform apply -var-file="terraform.prod.tfvars"
```

---

## 📊 Environment Comparison

| Aspect | Dev | Staging | Prod |
|--------|-----|---------|------|
| **Master** | t3.small | t3.medium | t3.large |
| **Workers** | 1 | 2 | 3 |
| **Volume** | 30 GB | 50 GB | 100 GB |
| **SSH Access** | 0.0.0.0/0 | 10.0.0.0/8 | YOUR IP ⚠️ |
| **VPC CIDR** | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| **Domain** | dev.k8s.example.com | staging.k8s.example.com | k8s.example.com |
| **Zone** | Create new | Create new | Use existing ⚠️ |

---

## 🔑 Key Features

### ✅ Count Loops
```hcl
# Control number of masters
master_count = 1  # Single master (typical)
# OR
master_count = 3  # HA cluster (advanced)

# Control number of workers
worker_count = 3  # Scale workers independently
```

### ✅ Environment Variables
All values now in `.tfvars` files:
- No more defaults in code
- Easy to version different environments
- Simple to switch between environments

### ✅ SSH & Security
```hcl
# Restrict SSH access by environment
# Dev: Open (0.0.0.0/0)
# Staging: VPC only (10.0.0.0/8)
# Prod: Your IP ONLY (203.0.113.0/24) ⚠️
admin_ssh_cidr = "YOUR.IP.RANGE/32"
```

---

## 📋 Production Gotchas ⚠️

### Before `terraform apply` in production:

1. **SSH CIDR** - Set to YOUR IP/VPN range
   ```hcl
   admin_ssh_cidr = "203.0.113.0/24"  # Change this!
   ```

2. **Domain Name** - Use your actual domain
   ```hcl
   domain_name = "your-domain.com"    # Change this!
   ```

3. **Route 53** - If zone already exists
   ```hcl
   create_route53_zone = false        # Change this!
   ```

4. **State Management** - Enable remote state
   - Ensure backend.tf has S3 configuration
   - Enable versioning on state bucket

5. **Review Plan** - ALWAYS review before apply
   ```bash
   terraform plan -var-file="terraform.prod.tfvars" > plan.txt
   # Review plan.txt carefully!
   ```

---

## 🔍 Debugging Commands

```bash
# Check what will be created
terraform plan -var-file="terraform.dev.tfvars"

# Show current state
terraform show

# List all resources
terraform state list

# Show specific resource
terraform state show module.k8s_master[0].aws_instance.master

# Get all output values
terraform output

# Get specific output
terraform output master_public_ips
```

---

## 📚 Documentation Files

| File | Purpose |
|------|---------|
| **TFVARS_GUIDE.md** | Complete guide to .tfvars files and variables |
| **UPDATE_SUMMARY.md** | Executive summary of all changes made |
| **FILES_CHANGED.md** | Detailed change log of all modifications |
| **QUICK_START.md** | This file - quick reference |

---

## 🎯 Common Scenarios

### Scenario 1: Scale from dev to prod
```bash
# Dev: Small cluster, open SSH
terraform apply -var-file="terraform.dev.tfvars"

# Destroy when ready
terraform destroy -var-file="terraform.dev.tfvars"

# Deploy prod: Large cluster, restricted SSH
terraform apply -var-file="terraform.prod.tfvars"
```

### Scenario 2: Add more workers
```bash
# Edit terraform.prod.tfvars
worker_count = 5  # Increase from 3

# Apply changes
terraform apply -var-file="terraform.prod.tfvars"
```

### Scenario 3: Create HA cluster (3 masters)
```bash
# Create custom tfvars:
# master_count = 3
# worker_count = 3

terraform apply -var-file="terraform.custom.tfvars"
```

---

## ✨ What Changed

### Before
```hcl
# Hard to manage multiple environments
variable "master_count" {
  default = 1  # Hard to change
}
```

### After
```hcl
# Easy to manage in tfvars files
# terraform.dev.tfvars
master_count = 1

# terraform.prod.tfvars
master_count = 3
```

---

## 🆘 Help!

### Error: "Variable not set"
```bash
# Make sure you use -var-file flag
terraform apply -var-file="terraform.dev.tfvars"  # ✅ Correct
terraform apply  # ❌ Wrong
```

### Error: "S3 bucket already exists"
```bash
# Bucket names must be globally unique
# Edit the tfvars file and change:
state_bucket_name = "unique-name-xyz"
```

### Error: "Module not installed"
```bash
# Run init first
terraform init
terraform validate
```

For more help, see TFVARS_GUIDE.md

---

## 📞 Quick Reference

| Task | Command |
|------|---------|
| Deploy dev | `terraform apply -var-file="terraform.dev.tfvars"` |
| Deploy staging | `terraform apply -var-file="terraform.staging.tfvars"` |
| Deploy prod | `terraform apply -var-file="terraform.prod.tfvars"` |
| Destroy dev | `terraform destroy -var-file="terraform.dev.tfvars"` |
| Preview changes | `terraform plan -var-file="FILE.tfvars"` |
| Check syntax | `terraform validate` |
| Format files | `terraform fmt -recursive .` |
| View outputs | `terraform output` |
| View state | `terraform show` |

---

**Status**: ✅ Ready to Use
**Last Updated**: March 24, 2025
**Version**: 1.0

👉 **Next Step**: Read TFVARS_GUIDE.md for detailed information
