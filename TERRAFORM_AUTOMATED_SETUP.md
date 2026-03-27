# Fully Automated RKE2 Cluster Setup via Terraform

## Overview

This guide describes the **fully automated** approach to provisioning and configuring a complete RKE2 Kubernetes cluster using Terraform provisioners. **Zero manual intervention required** — everything from infrastructure to cluster initialization happens with a single `terraform apply` command.

## What's Automated

✅ **Complete Automation Flow**:
1. Create VPC, subnets, security groups
2. Create EC2 master and worker instances
3. Wait for instances to be SSH-ready
4. Copy setup scripts to instances
5. **Execute master.sh on master node automatically**
6. **Execute worker.sh on all worker nodes automatically**
7. **Retrieve cluster token and kubeconfig locally**
8. **Return cluster verification commands**

**Result**: A fully functional RKE2 cluster ready for kubectl access

## Quick Start (3 Steps)

### Step 1: Configure Terraform Variables

```bash
cd infra/

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Key variables**:
```hcl
project_name         = "n8n"
cluster_name         = "n8n-dev"
environment          = "dev"
region               = "us-west-2"
master_count         = 1
worker_count         = 3
ssh_public_key       = ""              # Leave empty to auto-generate
ssh_private_key_path = ""              # Leave empty for auto-generated key
```

### Step 2: Provision Everything Automatically

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply - everything happens automatically!
terraform apply
```

**What happens**:
- ✓ Infrastructure created
- ✓ Master node setup starts automatically (via provisioner)
- ✓ Token generated on master
- ✓ Worker nodes join cluster automatically (via provisioner)
- ✓ Kubeconfig and token retrieved locally
- ✓ Output shows verification commands

### Step 3: Verify Cluster is Ready

After `terraform apply` completes, use the output commands:

```bash
# Export kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# Check cluster status
kubectl get nodes

# Should show:
# NAME                              STATUS   ROLES                AGE   VERSION
# ip-10-0-1-x.region.compute...     Ready    control-plane,etcd   5m    v1.27+rke2y
# ip-10-0-2-x.region.compute...     Ready    <none>               3m    v1.27+rke2y
# ip-10-0-2-y.region.compute...     Ready    <none>               3m    v1.27+rke2y
```

---

## Architecture

The automated setup uses Terraform provisioners at each stage:

```
Terraform Apply
  ├─ Phase 1: Infrastructure Creation
  │   ├─ Create VPC, Subnets
  │   ├─ Create Security Groups
  │   ├─ Create IAM Roles
  │   └─ Launch EC2 Instances (master + workers)
  │
  ├─ Phase 2: Master Node Setup (via provisioners)
  │   ├─ Wait for SSH availability (remote-exec)
  │   ├─ Copy master.sh to instance (file provisioner)
  │   ├─ Execute master.sh (remote-exec)
  │   └─ Retrieve token & kubeconfig (local-exec)
  │
  └─ Phase 3: Worker Node Setup (via provisioners) [depends-on master]
      ├─ Wait for SSH availability (remote-exec)
      ├─ Copy worker.sh to instances (file provisioner)
      └─ Execute worker.sh with master IP & token (remote-exec)

Result:
  ├─ kubeconfig-{environment}.yaml (local)
  ├─ rke2-token-{environment}.txt (local)
  └─ Functional RKE2 Cluster (ready for kubectl)
```

## Files Involved

### Terraform Modules (Updated for Automation)

| File | Change | Purpose |
|------|--------|---------|
| `infra/main.tf` | ✏️ Updated | Added ssh_private_key_path and scripts_dir inputs |
| `infra/variables.tf` | ✏️ Updated | Added ssh_private_key_path variable |
| `infra/outputs.tf` | ✏️ Updated | Added kubeconfig_path, cluster_token_path, verification commands |
| `modules/k8s_master/main.tf` | ✏️ Updated | Added provisioners for SSH wait, copy script, execute, retrieve files |
| `modules/k8s_master/variables.tf` | ✏️ Updated | Added ssh_private_key_path and scripts_dir variables |
| `modules/k8s_master/outputs.tf` | ✏️ Updated | Output rke2_token and kubeconfig_path |
| `modules/k8s_worker/main.tf` | ✏️ Updated | Added provisioners for SSH wait, copy script, execute |
| `modules/k8s_worker/variables.tf` | ✏️ Updated | Added ssh_private_key_path and scripts_dir variables |

### External Scripts (Called Automatically)

| Script | When | Purpose |
|--------|------|---------|
| `scripts/master.sh` | After master EC2 creation (via provisioner) | Initialize RKE2 server |
| `scripts/worker.sh` | After worker EC2 creation (via provisioner) | Join RKE2 cluster |

## How Provisioners Work

### Master Node Provisioners (in sequence)

```hcl
provisioner "remote-exec" {
  # Wait for cloud-init and SSH to be ready
  inline = ["cloud-init status --wait"]
  connection { ... }
}

provisioner "file" {
  # Copy master.sh script to instance
  source      = "scripts/master.sh"
  destination = "/tmp/master.sh"
  connection { ... }
}

provisioner "remote-exec" {
  # Execute master.sh with configuration options
  inline = [
    "chmod +x /tmp/master.sh",
    "/tmp/master.sh --domain ... --environment ... --project ... --rke2-version ..."
  ]
  connection { ... }
}

provisioner "local-exec" {
  # Retrieve token from master to local file
  command = "scp -i cluster-key.pem ubuntu@${master_ip}:/tmp/rke2-token.txt ./"
}

provisioner "local-exec" {
  # Retrieve kubeconfig from master to local file
  command = "scp -i cluster-key.pem ubuntu@${master_ip}:/home/ubuntu/.kube/config ./"
}
```

### Worker Node Provisioners (Dependencies)

```hcl
provisioner "remote-exec" {
  # Wait for cloud-init to complete
  inline = ["cloud-init status --wait"]
  connection { ... }
}

provisioner "file" {
  # Copy worker.sh to instance
  source      = "scripts/worker.sh"
  destination = "/tmp/worker.sh"
  connection { ... }
}

provisioner "remote-exec" {
  # Execute worker.sh with master IP and token from master output
  inline = [
    "chmod +x /tmp/worker.sh",
    "/tmp/worker.sh --master-ip ${master_private_ip} --token ${rke2_token} ..."
  ]
  connection { ... }
}

# Dependency: Workers only start after master provisioners complete
depends_on = [module.k8s_master]
```

## Configuration Options

### terraform.tfvars Example

```hcl
# Project Configuration
project_name = "n8n"
cluster_name = "n8n-production"
environment  = "prod"
owner        = "platform-team"

# AWS Configuration
aws_region         = "us-west-2"
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

# VPC Configuration
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

# SSH Key Configuration
ssh_public_key       = ""    # Leave empty to auto-generate cluster-key.pem
ssh_private_key_path = ""    # Leave empty to use auto-generated cluster-key.pem
                             # Or provide path if you supply ssh_public_key

# Instance Configuration
master_count          = 1
master_instance_type  = "t3.large"
worker_count          = 3
worker_instance_type  = "t3.medium"
node_volume_size      = 50
node_volume_type      = "gp3"

# RKE2 Configuration
rke2_version = "stable"  # or "v1.29", "latest", etc.
domain_name  = "k8s.example.com"

# Security Configuration
admin_ssh_cidr = "YOUR_PUBLIC_IP/32"  # Restrict to your IP!

# S3 Configuration
artifact_bucket_name = "n8n-artifacts-${aws_account_id}-unique-suffix"

# Route53 Configuration
create_route53_zone = false  # Set to true to create new zone, false for existing
```

## SSH Key Management

### Auto-Generated Keys (Recommended)

If you leave both variables empty:
```hcl
ssh_public_key       = ""
ssh_private_key_path = ""
```

Then:
- Terraform auto-generates a 4096-bit RSA key pair
- Private key saved to `infra/cluster-key.pem` (mode 0600)
- Public key added to EC2 instances via key pair

### Custom Keys (If You Provide Your Own)

If you provide your own public key:
```hcl
ssh_public_key       = "ssh-rsa AAAA..."
ssh_private_key_path = "~/.ssh/my-cluster-key"
```

Then:
- Custom public key used for EC2 instances
- Must provide path to corresponding private key
- Terraform uses it for provisioners

---

## Understanding the Output

After `terraform apply` completes, Terraform outputs useful information:

### Critical Outputs

```bash
# Get all outputs
terraform output

# Get specific outputs
terraform output -raw master_public_ip          # Master IP for SSH
terraform output -raw kubeconfig_path           # Kubeconfig location
terraform output -raw cluster_token_path        # Token location
terraform output -raw kubectl_access            # kubectl setup command
terraform output -raw cluster_verification_command  # Node verification
```

### Example Output Block

```
Outputs:

cluster_setup_status = "CLUSTER_SETUP_IN_PROGRESS"
cluster_token_path = "/path/to/infra/../rke2-token-dev.txt"
cluster_verification_command = "export KUBECONFIG=/path/to/infra/../kubeconfig-dev.yaml && kubectl get nodes"
kubectl_access = "export KUBECONFIG=/path/to/infra/../kubeconfig-dev.yaml"
kubeconfig_path = "/path/to/infra/../kubeconfig-dev.yaml"
master_public_ip = "54.xyz.abc.def"
worker_public_ips = [
  "52.abc.def.xyz",
  "52.abc.def.456",
  "52.abc.def.789"
]
```

---

## Monitoring the Setup

### Watch Terraform Apply in Real-Time

```bash
# See all provisioner output as it happens
terraform apply -auto-approve

# You'll see:
# aws_instance.master[0]: Provisioning with 'remote-exec'...
# aws_instance.master[0]: Waiting for cloud-init to complete...
# aws_instance.master[0]: Provisioning with 'file'...
# aws_instance.master[0]: Copying master.sh script...
# aws_instance.master[0]: Provisioning with 'remote-exec'...
# aws_instance.master[0]: Executing master.sh...
# ... (RKE2 install output) ...
# aws_instance.master[0]: RKE2 Master Node Setup Complete
```

### Check Master Log (During Apply)

Open another terminal to SSH to master while installation is happening:

```bash
ssh -i infra/cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>
tail -f /var/log/rke2-master-setup.log
```

### Check Worker Logs (During Apply)

```bash
ssh -i infra/cluster-key.pem ubuntu@<WORKER_PUBLIC_IP>
tail -f /var/log/rke2-worker-setup.log
```

---

## Troubleshooting

### Problem: Provisioner Fails to Connect

**Error**: `Error connecting: dial tcp <IP>: connection refused`

**Solutions**:
1. Verify security groups allow SSH (port 22)
2. Check if instance is fully booted: `aws ec2 describe-instance-status`
3. Try SSH manually to debug: `ssh -i cluster-key.pem ubuntu@<IP>`
4. Check cloud-init status: `cloud-init status`

### Problem: Master Script Fails During Provisioning

**Error**: Master setup script exits with error

**Solutions**:
1. Check instance resources: `free -m`, `df -h`
2. Verify internet connectivity on instance
3. Check main log: `tail -f /var/log/rke2-master-setup.log`
4. Re-run terraform apply to retry provisioning
5. Use `terraform taint` and `terraform apply` to force re-provisioning

```bash
# Force re-provisioning of master node
terraform taint module.k8s_master[0].aws_instance.master
terraform apply -auto-approve
```

### Problem: Workers Can't Join Cluster

**Error**: Worker script fails to connect to master

**Solutions**:
1. Verify master is fully ready: `curl -sk https://<MASTER_IP>:6443/healthz`
2. Check security group allows port 9345 from workers to master
3. Check token is valid: `cat infra/rke2-token-dev.txt`
4. Check network connectivity: `ssh ubuntu@WORKER && nc -zv <MASTER_IP> 9345`
5. Re-run terraform apply to retry worker provisioners

### Problem: Can't Retrieve Kubeconfig/Token

**Symptoms**: Files not found in project root after terraform apply

**Solutions**:
```bash
# Check if provisioners completed
terraform state list | grep provisioner

# Manually retrieve files
scp -i infra/cluster-key.pem ubuntu@<MASTER_IP>:/tmp/rke2-token.txt ./rke2-token-dev.txt
scp -i infra/cluster-key.pem ubuntu@<MASTER_IP>:~/.kube/config ./kubeconfig-dev.yaml

# Verify file exists
ls -la kubeconfig-dev.yaml rke2-token-dev.txt
```

---

## Verification Steps

### After terraform apply Completes

```bash
# 1. Export kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig-dev.yaml

# 2. Check cluster version
kubectl version

# 3. Check all nodes are Ready
kubectl get nodes -o wide

# 4. Check system pods are running
kubectl get pods -A

# 5. Check master node details
kubectl describe node <MASTER_NODE_NAME>

# 6. Deploy a test pod
kubectl run test-pod --image=nginx:latest
kubectl get pods
kubectl delete pod test-pod
```

### Expected Output

```bash
$ kubectl get nodes -o wide

NAME                       STATUS   ROLES                AGE   VERSION        INTERNAL-IP   EXTERNAL-IP
ip-10-0-1-10.compute...    Ready    control-plane,etcd   10m   v1.27.1+rke2   10.0.1.10     <none>
ip-10-0-2-20.compute...    Ready    <none>               6m    v1.27.1+rke2   10.0.2.20     <none>
ip-10-0-2-30.compute...    Ready    <none>               5m    v1.27.1+rke2   10.0.2.30     <none>
ip-10-0-2-40.compute...    Ready    <none>               5m    v1.27.1+rke2   10.0.2.40     <none>
```

All nodes should show:
- ✓ STATUS: Ready
- ✓ ROLES: control-plane,etcd (master), none (workers)
- ✓ VERSION: Same RKE2 version (v1.27, v1.28, etc.)

---

## Advanced Configuration

### Custom RKE2 Configuration

To pass additional RKE2 options to both master and workers, edit the provisioner commands in:
- `modules/k8s_master/main.tf` — master.sh provisioner
- `modules/k8s_worker/main.tf` — worker.sh provisioner

Example: Custom CNI, logging level, etc.

```bash
# In master provisioner, add options:
./master.sh \
  --domain k8s.example.com \
  --environment prod \
  --rke2-version v1.29 \
  --additional-san 10.0.0.1 \
  --log-level debug
```

### Scaling Workers After Deployment

To add more workers after initial deployment:

```bash
# Update terraform.tfvars
worker_count = 5  # Changed from 3

# Apply changes - new workers are provisioned automatically
terraform apply -auto-approve
```

Terraform will:
1. Create new EC2 instances
2. Run provisioners automatically (copy script, execute)
3. New workers join existing cluster
4. Output updated worker lists

### Replacing a Node

To replace a node (master or worker):

```bash
# Find the resource to replace
terraform state list | grep aws_instance

# Taint it to force replacement
terraform taint 'module.k8s_master[0].aws_instance.master'

# Apply - old instance destroyed, new one created with provisioners
terraform apply -auto-approve
```

---

## Security Considerations

### SSH Key Management
- ✓ Private key stored locally (cluster-key.pem)
- ✓ Never commit private key to git (.gitignore prevents this)
- ✓ Set proper permissions: `chmod 600 cluster-key.pem`

### Kubeconfig Management
- ✓ Retrieved locally after cluster setup
- ⚠️ Contains admin credentials — treat as secret
- ⚠️ Don't commit to git
- ✓ Restrict file permissions: `chmod 600 kubeconfig-*.yaml`

### API Access
- ✓ Kubeconfig uses auto-signed certs (self-signed)
- ✓ kubectl authenticates using certificate
- ⚠️ Restrict API access via security groups and RBAC

### Network Security
- ✓ Security groups restrict traffic to necessary ports
- ✓ Master API (6443) accessible from specific CIDR
- ✓ Worker nodes (10250) restricted to master/worker CIDR
- ✓ SSH (22) restricted to admin_ssh_cidr

---

## Cleanup

### Destroy Everything

To remove all AWS resources:

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm when prompted
# Type 'yes' to confirm

# Verify deletion
aws ec2 describe-instances --filters "Name=tag:Name,Values=*n8n*"
```

This will delete:
- EC2 instances (master + workers)
- VPC and subnets
- Security groups
- EBS volumes
- Elastic IPs
- IAM roles
- Everything except S3 (if created manually)

### Keep Only Infrastructure (Teardown Cluster)

To destroy cluster but keep VPC:

```bash
# Destroy specific modules
terraform destroy -target 'module.k8s_master' -target 'module.k8s_workers'
```

---

## Performance Metrics

### Typical Deployment Times

| Phase | Duration | What's Happening |
|-------|----------|-----------------|
| Initialize Terraform | ~30s | Download/validate modules |
| Plan | ~30s | Analyze changes |
| Create Infrastructure | ~3-5 min | VPC, security groups, IAM |
| Wait for SSH | ~1-2 min | Instances boot, cloud-init runs |
| Master Setup | ~5-10 min | RKE2 install, API startup |
| Token Retrieval | ~10s | SCP token from master |
| Worker Setup | ~3-5 min each | RKE2 agent install per worker |
| **Total** | **~15-25 min** | **Full cluster ready** |

### Resource Usage

Default configuration creates:
- 1 master: t3.large (2 vCPU, 8GB RAM) = ~$0.10/hour
- 3 workers: t3.medium (2 vCPU, 4GB RAM) = ~$0.05/hour each
- EBS volumes: 50GB gp3 each = ~$3/month each
- **Total**: ~$0.25/hour running cost (~$180/month)

---

## Monitoring and Observability

### Check Provisioner Execution

```bash
# View terraform state to see provisioner results
terraform state show 'module.k8s_master[0].aws_instance.master'

# Look for sections like:
# provisioner "remote-exec" { ... }
# provisioner "file" { ... }
# provisioner "local-exec" { ... }
```

### Real-Time Monitoring During Terraform Apply

Watch provisioner output:
```bash
# Terminal 1: Run terraform
terraform apply

# Terminal 2: SSH to instances while provisioning happens
ssh -i cluster-key.pem ubuntu@MASTER_IP
tail -f /var/log/rke2-master-setup.log

# Terminal 3: Monitor AWS CLI
watch -n 5 'aws ec2 describe-instance-status --instance-ids i-xxx'
```

### Post-Deployment Observability

```bash
# Cluster information
export KUBECONFIG=kubeconfig-dev.yaml
kubectl cluster-info

# Node status
kubectl get nodes -o wide

# System component status
kubectl get pods -A | grep -E 'helm|coredns|etcd|rke2'

# Master node logs
ssh -i cluster-key.pem ubuntu@MASTER_IP
sudo journalctl -u rke2-server -n 50

# Worker node logs
ssh -i cluster-key.pem ubuntu@WORKER_IP
sudo journalctl -u rke2-agent -n 50
```

---

## Appendix: What Changed From Manual Approach

### Before (Manual)

```bash
# Phase 1: Create infrastructure
terraform apply

# Phase 2: Manual SSH to master
ssh -i cluster-key.pem ubuntu@MASTER_IP

# Phase 3: Manual script execution
./master.sh --domain ...

# Phase 4: Manual token retrieval
TOKEN=$(cat /tmp/rke2-token.txt)

# Phase 5: Manual SSH to each worker
for worker in workers; do
  ssh -i cluster-key.pem ubuntu@$worker
  ./worker.sh --master-ip ... --token $TOKEN
done

# Result: Takes human effort, error-prone, manual steps
```

### After (Fully Automated)

```bash
# Everything happens automatically!
terraform apply

# Result: Complete cluster ready, token+kubeconfig retrieved, minimal human effort
```

### Summary of Changes

| Aspect | Before | After |
|--------|--------|-------|
| **Manual Steps** | 8+ manual commands | 0 manual commands |
| **Time to Cluster** | 30+ minutes (if no errors) | 15-25 minutes |
| **Error-Prone** | Yes (scripting, timing) | No (pure Terraform) |
| **Idempotent** | No (can't re-run safely) | Yes (Terraform handles it) |
| **Observable** | Partially (need terminal per node) | Fully (terraform output shows everything) |
| **Automation-Ready** | Requires wrapper scripts | Fully automated |
| **Infrastructure as Code** | Both IAC and scripts | Pure IAC (Terraform) |

---

## FAQ

### Q: How long does terraform apply take?

A: 15-25 minutes depending on AWS region and instance sizes. Master setup is the longest part (~10 min).

### Q: What if a provisioner fails halfway?

A: Terraform will error and show which provisioner failed. You can:
1. Fix the issue (e.g., add an SSH key)
2. Run `terraform apply` again to retry all provisioners
3. Or use `terraform taint` to target specific resources

### Q: Can I use my own SSH key?

A: Yes! Set `ssh_public_key` to your key and `ssh_private_key_path` to the path of your private key.

### Q: Can I scale workers after deployment?

A: Yes! Update `worker_count` in terraform.tfvars and run `terraform apply`. New workers are provisioned automatically.

### Q: What's the cluster token used for?

A: Workers use it to authenticate with the master and join the cluster. The token is retrieved after master setup completes.

### Q: Can I keep the kubeconfig and token for later use?

A: Yes! They're saved in your project root:
- `kubeconfig-{environment}.yaml` — kubectl config
- `rke2-token-{environment}.txt` — cluster token

Both are in `.gitignore` so they won't be committed.

### Q: What if terraform destroy fails?

A: Common reasons:
- Security group has dependencies
- Termination protection enabled
- Manual changes to resources

**Solution**: Use `terraform destroy -auto-approve` and check AWS console for remaining resources.

---

## Support and Next Steps

### Getting Help

1. **Check logs on instances**:
   ```bash
   ssh -i cluster-key.pem ubuntu@<MASTER_IP>
   tail -f /var/log/rke2-master-setup.log
   ```

2. **Review Terraform state**:
   ```bash
   terraform state show <resource>
   terraform state list
   ```

3. **Check AWS console** for instance health and status

### Next Steps After Cluster is Ready

1. **Deploy applications**:
   ```bash
   kubectl apply -f my-app.yaml
   ```

2. **Setup ingress controller**:
   ```bash
   helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
   ```

3. **Install monitoring**:
   ```bash
   helm install prometheus prometheus-community/kube-prometheus-stack
   ```

4. **Configure DNS**:
   - Point domain to master's EIP
   - Or use load balancer

5. **Backup kubeconfig**:
   ```bash
   cp kubeconfig-dev.yaml ~/.kube/config.backup
   ```

---

**Status**: ✅ Fully Automated RKE2 Cluster Setup via Terraform

Last Updated: March 27, 2025
