# RKE2 Cluster Setup Guide

This guide provides step-by-step instructions for setting up an RKE2 Kubernetes cluster using external setup scripts instead of embedded user_data templates.

## Overview

The cluster setup is split into two phases:

1. **Infrastructure Provisioning** (Terraform) - Creates VPC, EC2 instances, security groups, and storage
2. **Cluster Initialization** (Script-based) - Sets up RKE2 server and agents on the provisioned instances

This approach provides:
- ✅ Better control over cluster initialization
- ✅ Easier debugging and logging
- ✅ More reliable and predictable cluster setup
- ✅ Cleaner Terraform code
- ✅ Production-friendly architecture

---

## Prerequisites

1. **AWS Account** with appropriate permissions:
   - EC2 (create instances, security groups, networking)
   - S3 (state bucket and artifacts)
   - IAM (roles and policies)
   - Route53 (DNS)

2. **Local Tools**:
   - Terraform (`>= 1.1`)
   - AWS CLI configured with credentials
   - SSH client
   - curl or wget

3. **SSH Key**:
   - Generate a key pair or use existing:
     ```bash
     ssh-keygen -t rsa -b 4096 -f ~/.ssh/rke2-cluster
     # Or use existing key in terraform.tfvars
     ```

---

## Phase 1: Infrastructure Provisioning

### Step 1.1: Prepare Terraform Variables

Create or update `terraform.tfvars`:

```hcl
project_name         = "n8n"
cluster_name         = "n8n-dev"
environment          = "dev"
region               = "us-west-2"
availability_zones   = ["us-west-2a", "us-west-2b"]

# SSH Configuration
ssh_public_key = ""  # Leave empty to auto-generate, or provide ~./id_rsa.pub

# Instance Configuration
master_count          = 1
master_instance_type  = "t3.large"
worker_count          = 3
worker_instance_type  = "t3.medium"
node_volume_size      = 50
node_volume_type      = "gp3"

# RKE2 Configuration
rke2_version = "stable"  # or "v1.27", "latest", etc.

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
admin_ssh_cidr       = "0.0.0.0/0"  # Restrict to your IP for security

# DNS (optional)
domain_name = "k8s.example.com"
route53_zone_id = "Z1234567890ABC"  # Optional

# S3 Buckets
artifact_bucket_name = "n8n-artifacts-unique-name"

# IAM Roles (optional, auto-created if not provided)
# instance_role_name = "n8n-node-role"
```

> ⚠️ **Security Note**: In production, restrict `admin_ssh_cidr` to your specific IP address or VPN range, not `0.0.0.0/0`.

### Step 1.2: Initialize and Plan Terraform

```bash
cd infra/

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Review planned changes
terraform plan -out=tfplan
```

### Step 1.3: Apply Terraform Configuration

```bash
# Apply the plan to create infrastructure
terraform apply tfplan

# This will create:
# - VPC with public subnets and security groups
# - Master node(s)
# - Worker node(s)
# - IAM roles and policies
# - SSH key pair (if not provided)
# - Outputs with IP addresses
```

### Step 1.4: Capture Output Information

```bash
# Save outputs for reference
terraform output -json > ../cluster-outputs.json

# Display key information
echo "=== Cluster Information ==="
terraform output master_public_ip
terraform output master_private_ips
terraform output worker_public_ips
terraform output ssh_master_command
terraform output ssh_worker_commands
```

**Keep these values handy:**
- Master public IP → for SSH access
- Master private IP → for worker configuration
- Worker public IPs → for SSH access to workers
- Key pair location → usually `./cluster-key.pem` if auto-generated

---

## Phase 2: Cluster Initialization

### Step 2.1: Connect to Master Node

Use the SSH command from Terraform outputs:

```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>

# Verify system is ready
sudo systemctl status systemd-networkd
sudo ip addr show
```

### Step 2.2: Run Master Setup Script

On the master node, execute the setup script:

```bash
# Download or copy the master script
# (Assuming you've transferred it to the instance)

# Make it executable
chmod +x master.sh

# Run the master setup with options
./master.sh \
  --domain k8s.example.com \
  --environment dev \
  --project n8n \
  --rke2-version stable

# Expected output:
# [timestamp] RKE2 Master Node Setup Starting
# [timestamp] Installing system packages...
# [timestamp] Disabling swap...
# ...
# [timestamp] ✓ RKE2 Master Node Setup Complete
```

**Monitor the logs:**
```bash
# In another terminal, SSH to master and monitor logs
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>
tail -f /var/log/rke2-master-setup.log
```

### Step 2.3: Verify Master is Ready

```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>

# Check RKE2 server status
sudo systemctl status rke2-server

# Verify API is responding
sudo curl -sk https://localhost:6443/healthz

# Check if supervisor port is reachable
sudo nc -zv 127.0.0.1 9345

# Retrieve the cluster token for workers
cat /tmp/rke2-token.txt

# Display cluster info
cat /tmp/rke2-cluster-info.txt
```

**Success indicators:**
- `rke2-server` service is active
- Port 9345 is listening
- `/tmp/rke2-token.txt` contains a valid token
- API responds to health checks

### Step 2.4: Retrieve Cluster Token

The token is automatically saved on the master in `/tmp/rke2-token.txt`:

```bash
# From master node
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>
cat /tmp/rke2-token.txt
```

Or retrieve via local machine:
```bash
# Copy token from master to local machine
scp -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>:/tmp/rke2-token.txt ./rke2-token.txt

# Or display directly
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP> cat /tmp/rke2-token.txt
```

### Step 2.5: Connect to Worker Nodes

For each worker node, SSH in and run the worker setup script:

```bash
# Get worker public IP from Terraform output
WORKER_PUBLIC_IP=$(terraform output -json worker_public_ips | jq -r '.[0]')

# Get master private IP
MASTER_PRIVATE_IP=$(terraform output master_private_ip)

# Get the cluster token (from /tmp/rke2-token.txt on master or locally)
CLUSTER_TOKEN=$(cat rke2-token.txt)

# SSH to worker
ssh -i cluster-key.pem ubuntu@${WORKER_PUBLIC_IP}
```

### Step 2.6: Run Worker Setup Script

On each worker node:

```bash
# Make script executable
chmod +x worker.sh

# Run with master IP and token
./worker.sh \
  --master-ip <MASTER_PRIVATE_IP> \
  --token <CLUSTER_TOKEN> \
  --environment dev \
  --project n8n \
  --rke2-version stable

# Expected output:
# [timestamp] RKE2 Worker Node Setup Starting
# [timestamp] Installing system packages...
# ...
# [timestamp] ✓ RKE2 Worker Node Setup Complete
```

**Monitor the logs:**
```bash
tail -f /var/log/rke2-worker-setup.log
```

### Step 2.7: Verify All Nodes Joined

Execute this command on the master node:

```bash
# SSH to master (if not already there)
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>

# Set kubeconfig
export KUBECONFIG=/home/ubuntu/.kube/config

# Check node status
kubectl get nodes -o wide

# Expected output (example):
# NAME                              STATUS   ROLES                 AGE   VERSION
# ip-10-0-1-10.us-west-2.compute    Ready    control-plane,etcd    8m    v1.27.x+rke2y
# ip-10-0-2-20.us-west-2.compute    Ready    <none>                3m    v1.27.x+rke2y
# ip-10-0-2-30.us-west-2.compute    Ready    <none>                2m    v1.27.x+rke2y
```

All nodes should show:
- **STATUS**: `Ready`
- **ROLES**: `control-plane,etcd` for master, `<none>` for workers

---

## Cluster Verification

### Verify Cluster Health

```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>

# Set KUBECONFIG
export KUBECONFIG=/home/ubuntu/.kube/config

# Check all nodes
kubectl get nodes -o wide

# Check pods
kubectl get pods -A

# Check system components
kubectl get all -n kube-system

# Check cluster info
kubectl cluster-info

# Check node details
kubectl describe node <NODE_NAME>
```

### Verify RKE2 Services

```bash
# Check master service
sudo systemctl status rke2-server

# Check logs
sudo journalctl -u rke2-server -n 50

# Check kubelet
sudo systemctl status rke2-server
sudo ps aux | grep rke2

# Check ports
sudo netstat -tlnp | grep rke2
```

### Deploy Test Workload

```bash
# Deploy a simple test deployment
kubectl create deployment nginx --image=nginx:latest
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Check deployment
kubectl get deployment,svc,pods

# Delete test deployment
kubectl delete deployment nginx
kubectl delete svc nginx
```

---

## Troubleshooting

### Master Setup Fails

**Symptoms**: Master script exits with error early

**Solution**:
1. Check logs: `tail -f /var/log/rke2-master-setup.log`
2. Check system resources: `free -m`, `df -h`
3. Check internet connectivity: `curl https://get.rke2.io`
4. Verify ports are open: `sudo netstat -tlnp | grep LISTEN`
5. Re-run script with more verbose output

### Worker Cannot Reach Master

**Symptoms**: Worker script fails with "Could not reach master at <IP>:9345"

**Solution**:
1. Verify master private IP is correct
2. Check security group allows port 9345 from workers
3. SSH to master and verify port is listening:
   ```bash
   sudo netstat -tlnp | grep :9345
   ```
4. Check network connectivity from worker:
   ```bash
   ssh -i cluster-key.pem ubuntu@<WORKER_IP>
   ping <MASTER_PRIVATE_IP>
   nc -zv <MASTER_PRIVATE_IP> 9345
   ```

### Worker Does Not Join Cluster

**Symptoms**: Worker script completes but node doesn't appear in `kubectl get nodes`

**Solution**:
1. Check worker logs: `ssh -i cluster-key.pem ubuntu@<WORKER_IP> && tail -f /var/log/rke2-worker-setup.log`
2. Verify RKE2 agent is running: `sudo systemctl status rke2-agent`
3. Check agent logs: `sudo journalctl -u rke2-agent -n 100`
4. Verify token is correct: Compare token on master and worker config
5. Check API connectivity: `curl -k https://<MASTER_IP>:6443/healthz`

### Invalid Token Error

**Symptoms**: Worker error: "invalid cluster token" or similar

**Solution**:
1. Verify token from master: `cat /tmp/rke2-token.txt`
2. Token should be a long string (100+ characters)
3. Re-run master script if token is missing
4. Copy exact token to worker (no whitespace)

### Master API Not Ready

**Symptoms**: Master setup times out waiting for API

**Solution**:
1. Check master logs: `tail -f /var/log/rke2-master-setup.log`
2. Check service status: `sudo systemctl status rke2-server`
3. Check service logs: `sudo journalctl -u rke2-server -n 50`
4. Verify system has enough resources: `free -m`, `df -h`
5. Wait longer: RKE2 may take 5-10 minutes on slower systems
6. Re-run script after verifying system is healthy

---

## Scripts Reference

### master.sh

Initializes the RKE2 server (master/control-plane node).

**Usage**:
```bash
./master.sh [OPTIONS]
```

**Options**:
- `--domain <domain>` — Domain name for TLS SANs (optional)
- `--environment <env>` — Environment name (default: dev)
- `--project <name>` — Project name (default: n8n)
- `--rke2-version <version>` — RKE2 version (default: stable)

**Output Files**:
- `/var/log/rke2-master-setup.log` — Setup script log
- `/tmp/rke2-token.txt` — Cluster join token
- `/tmp/rke2-cluster-info.txt` — Cluster summary information
- `/home/ubuntu/.kube/config` — kubectl configuration

### worker.sh

Joins a worker node to an existing RKE2 cluster.

**Usage**:
```bash
./worker.sh --master-ip <IP> --token <TOKEN> [OPTIONS]
```

**Required Options**:
- `--master-ip <IP>` — Master node private IP address
- `--token <TOKEN>` — Cluster join token from master

**Optional Options**:
- `--environment <env>` — Environment name (default: dev)
- `--project <name>` — Project name (default: n8n)
- `--rke2-version <version>` — RKE2 version (default: stable)

**Output Files**:
- `/var/log/rke2-worker-setup.log` — Setup script log

---

## Network Architecture

```
┌─────────────────────────────────────────────────────┐
│                     VPC (10.0.0.0/16)               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Public Subnet (10.0.1.0/24)                 │  │
│  │  ┌────────────────────────────────────────┐  │  │
│  │  │ Master Node (Control Plane)            │  │  │
│  │  │ - Private IP: 10.0.1.x                 │  │  │
│  │  │ - Public IP/EIP: Elastic IP            │  │  │
│  │  │ - Ports: SSH(22), API(6443), RKE2(9345)│  │  │
│  │  └────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Public Subnet (10.0.2.0/24)                 │  │
│  │  ┌────────────────────────────────────────┐  │  │
│  │  │ Worker Node 1                          │  │  │
│  │  │ - Private IP: 10.0.2.x                 │  │  │
│  │  │ - Public IP/EIP: Elastic IP            │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────┐  │  │
│  │  │ Worker Node 2                          │  │  │
│  │  │ - Private IP: 10.0.2.y                 │  │  │
│  │  │ - Public IP/EIP: Elastic IP            │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────┐  │  │
│  │  │ Worker Node 3                          │  │  │
│  │  │ - Private IP: 10.0.2.z                 │  │  │
│  │  │ - Public IP/EIP: Elastic IP            │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘

Communication Flows:
- Local SSH: Public IP → port 22 (admin CIDR)
- Remote kubectl: Public IP → port 6443 (API, restricted)
- Worker Join: Private IP → port 9345 (supervisor)
- Pod Networking: Private IP → 8472 UDP (VXLAN)
- Kubelet: Port 10250 (master-worker)
```

---

## Security Considerations

1. **SSH Access**:
   - Restrict `admin_ssh_cidr` to your IP or VPN
   - Rotate SSH keys regularly
   - Use strong key passphrases

2. **Cluster Token**:
   - Treat token as a secret; don't commit to git
   - Rotate tokens periodically
   - Delete `/tmp/rke2-token.txt` after workers are set up

3. **Security Groups**:
   - Restrict API (6443) access to needed clients
   - Limit NodePort services to internal/VPN only
   - Consider using Network ACLs for additional control

4. **RBAC**:
   - Implement Kubernetes RBAC policies
   - Create service accounts for applications
   - Audit cluster access regularly

5. **Node Updates**:
   - Plan maintenance windows
   - Update nodes one at a time
   - Use drain/cordon to safely evict pods

---

## Next Steps

1. **Deploy Applications**:
   ```bash
   kubectl apply -f deployment.yaml
   ```

2. **Setup Ingress Controller**:
   - Deploy NGINX Ingress or Traefik
   - Configure DNS to point to ingress

3. **Install Monitoring**:
   - Deploy Prometheus and Grafana
   - Configure alerting

4. **Setup Persistent Storage**:
   - Configure EBS volumes (AWS EBS CSI Driver)
   - Setup backup strategy

5. **CI/CD Integration**:
   - Connect to git repository
   - Deploy ArgoCD or Flux for GitOps

---

## Support & Maintenance

**Logs Location**:
- Master setup: `/var/log/rke2-master-setup.log`
- Master service: `sudo journalctl -u rke2-server -n 50`
- Worker setup: `/var/log/rke2-worker-setup.log`
- Worker service: `sudo journalctl -u rke2-agent -n 50`

**Verification Commands**:
```bash
# Overall status
kubectl get nodes -o wide
kubectl get all -A

# System components
kubectl get all -n kube-system

# Cluster info
kubectl cluster-info dump --all-namespaces

# Node details
kubectl describe nodes
```

**Version Info**:
- Check installed RKE2 version: `rke2 --version`
- Check Kubernetes version: `kubectl version`
- Check kubelet version: `kubectl get nodes -o wide`

---

## Document History

| Date | Version | Changes |
|------|---------|---------|
| 2025-01-15 | 1.0 | Initial creation - moved from user_data to external scripts |

For questions or issues, refer to:
- RKE2 Documentation: https://docs.rke2.io/
- Kubernetes Documentation: https://kubernetes.io/docs/
- AWS RKE2 Troubleshooting: https://github.com/rancher/rke2/discussions
