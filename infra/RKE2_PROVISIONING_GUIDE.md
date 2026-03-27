# RKE2 Cluster Provisioning Guide

## Overview

This guide documents the fixed RKE2 Kubernetes cluster provisioning process, which ensures reliable master-to-worker node coordination and successful cluster initialization.

---

## Changes Made

### 1. Master Node Initialization (`modules/k8s_master/userdata.sh.tpl`)

**Key Improvements:**
- ✓ **Token Verification**: RKE2 generates a token and verifies it's created in `/var/lib/rancher/rke2/server/node-token`
- ✓ **API Health Check**: Waits for Kubernetes API server to respond on `localhost:6443`
- ✓ **SSM Parameter Verification**: Checks token was stored correctly in AWS SSM Parameter Store
- ✓ **Error Handling**: Exits with detailed error messages if any step fails
- ✓ **Logging**: All events logged to `/var/log/rke2-bootstrap.log`

**Master Initialization Timeline:**
```
1. System preparation (2-3 minutes)
   - Install prerequisites (curl, git, jq, awscli)
   - Configure kernel parameters
   - Load network modules

2. RKE2 Installation (3-5 minutes)
   - Download RKE2 installer
   - Configure with generated cluster token

3. Cluster Initialization (2-5 minutes)
   - Start RKE2 server service
   - Wait for service to become active

4. API Verification (1-2 minutes)
   - Verify kubeconfig created
   - Setup kubectl access

5. Token Publishing (1 minute)
   - Store token in SSM Parameter Store
   - Verify token stored correctly

Total Expected Time: 10-15 minutes
```

### 2. Worker Node Initialization (`modules/k8s_worker/userdata.sh.tpl`)

**Key Improvements:**
- ✓ **Master Readiness Check**: TCP connection test to `master_private_ip:9345` with 60 retries (10 minutes)
- ✓ **Token Retrieval with Retry**: Attempts to get token from SSM for up to 30 minutes (60 retries × 30 seconds)
- ✓ **Token Validation**: Verifies token length is valid (> 10 bytes)
- ✓ **RKE2 Agent Installation**: Downloads and installs RKE2 agent
- ✓ **Cluster Join**: Connects to master using supervisor port (9345)
- ✓ **Error Handling**: Exits with detailed error messages if any step fails
- ✓ **Logging**: All events logged to `/var/log/rke2-agent-bootstrap.log`

**Worker Initialization Timeline:**
```
1. System preparation (2-3 minutes)
   - Install prerequisites

2. Master Readiness Check (1-10 minutes)
   - TCP test to master:9345
   - Waits up to 10 minutes for master to boot

3. Token Retrieval (1-30 minutes)
   - Retrieves token from SSM Parameter Store
   - Waits up to 30 minutes for master to initialize
   - Polls every 30 seconds

4. RKE2 Agent Installation (3-5 minutes)
   - Download RKE2 installer
   - Configure agent with master URL and token

5. Cluster Join (1-2 minutes)
   - Start RKE2 agent service
   - Agent connects to master and joins cluster

Total Expected Time: 10-50 minutes (depending on master readiness)
```

### 3. Terraform Dependency (`main.tf`)

**Explicit Dependency Added:**
```hcl
depends_on = [
  module.k8s_master
]
```

This ensures:
- Workers module waits for master resource creation
- Prevents parallel execution that could cause race conditions
- Master has time to initialize before workers attempt to join

---

## Network Requirements

The security groups allow the following traffic:

| Protocol | Ports | Description |
|----------|-------|-------------|
| TCP | 22 | SSH access from admin networks |
| TCP | 6443 | Kubernetes API server from admin and workers |
| TCP | 9345 | RKE2 supervisor/agent connection from workers |
| TCP | 10250 | Kubelet from master to workers |
| UDP | 8472 | VXLAN overlay networking |
| TCP | 30000-32767 | Kubernetes NodePort services |

---

## Deployment Instructions

### Step 1: Validate Configuration

```bash
cd /home/ahsan-malik/Desktop/n8n-infra-deployment/infra

# Validate Terraform
terraform validate

# Plan deployment
terraform plan -out=tfplan
```

### Step 2: Deploy Infrastructure

```bash
# Apply the plan (this will take 15-20 minutes)
terraform apply "tfplan"

# Save outputs
terraform output > deployment-outputs.txt
cat deployment-outputs.txt
```

### Step 3: Monitor Master Node Initialization

Once master instance is created:

```bash
# Get master instance ID
MASTER_ID=$(terraform output -json | jq -r '.master_instance_ids[0]')
MASTER_IP=$(terraform output -json | jq -r '.master_public_ips[0]')

# SSH to master (using the generated key)
ssh -i cluster-key.pem ubuntu@$MASTER_IP

# Check bootstrap log
tail -f /var/log/rke2-bootstrap.log

# Wait for these messages:
# [timestamp] ✓ Token successfully stored and verified in SSM
# [timestamp] ✓ RKE2 master bootstrap complete
# [timestamp] Master node ready. Workers can now join the cluster.
```

### Step 4: Monitor Worker Node Initialization

Once worker instances are created:

```bash
# SSH to first worker
WORKER_IP=$(terraform output -json | jq -r '.worker_public_ips[0]')
ssh -i cluster-key.pem ubuntu@$WORKER_IP

# Check bootstrap log
tail -f /var/log/rke2-agent-bootstrap.log

# Wait for these messages:
# [timestamp] Master API is reachable
# [timestamp] ✓ Token retrieved successfully from SSM
# [timestamp] ✓ RKE2 agent bootstrap complete
# [timestamp] Worker node should be joining the cluster...
```

---

## Cluster Verification

### Verify from Master Node

Once all nodes are initialized:

```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@$MASTER_IP

# Set kubeconfig
export KUBECONFIG=/home/ubuntu/.kube/config

# List all nodes
kubectl get nodes

# Expected output (example with 3 workers):
# NAME                         STATUS   ROLES                  AGE    VERSION
# ip-10-0-1-xxx.ec2.internal  Ready    control-plane,master   5m     v1.27.x
# ip-10-0-2-xxx.ec2.internal  Ready    <none>                 2m     v1.27.x
# ip-10-0-3-xxx.ec2.internal  Ready    <none>                 2m     v1.27.x
# ip-10-0-4-xxx.ec2.internal  Ready    <none>                 2m     v1.27.x

# Check node status details
kubectl describe nodes

# Check system pods
kubectl get pods -n kube-system

# Verify Canal CNI is installed
kubectl get daemonset -n kube-system -A
```

### Verify Network Connectivity

```bash
# Check VXLAN overlay is working
kubectl get pods -n kube-system | grep -E "(canal|flannel)"

# Test inter-pod communication
kubectl run test-pod --image=busybox --command -- sleep 3600
kubectl get pod test-pod -o wide

# From another pod, test DNS and connectivity
kubectl exec -it <pod-name> -- sh
# Inside pod:
# ping <service-name>
# nslookup <service-name>
```

---

## Troubleshooting

### Master Node Fails to Initialize

**Symptom:** Bootstrap log shows failures, master instance is running but cluster not initialized

**Check:**
```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@$MASTER_IP

# Check RKE2 service status
systemctl status rke2-server

# Check detailed logs
journalctl -u rke2-server -n 100

# Check that node-token file was created
ls -la /var/lib/rancher/rke2/server/node-token
```

**Common Issues:**
- Not enough disk space (50GB minimum)
- Memory constraints (2GB minimum for small master)
- Network connectivity issues

### Worker Nodes Fail to Join

**Symptom:** Workers are running but not appearing in `kubectl get nodes`

**Check:**
```bash
# SSH to worker
ssh -i cluster-key.pem ubuntu@$WORKER_IP

# Check agent service status
systemctl status rke2-agent

# Check detailed logs
journalctl -u rke2-agent -n 100

# Check RKE2 agent logs
cat /var/log/rke2-agent-bootstrap.log

# Verify connectivity to master port 9345
telnet $MASTER_PRIVATE_IP 9345
# Should show "Connected"
```

**Common Issues:**
- Master port 9345 not reachable (network/security group issue)
- Token not available in SSM (master not finished initializing)
- Token mismatch (master used different token generation)

### Check Token in SSM

```bash
# From local machine or master
aws ssm get-parameter \
  --name "/n8n-k8s/dev/rke2/token" \
  --with-decryption \
  --region us-east-1 \
  --query 'Parameter.Value'

# Should return the cluster token
```

### Node Status Issues

```bash
# Check node NotReady status details
kubectl describe node <node-name>

# Check kubelet logs on that node
ssh -i cluster-key.pem ubuntu@<node-ip>
journalctl -u rke2-agent -n 50

# Common causes: DNS issues, network plugin not ready, resource constraints
```

---

## Post-Deployment Steps

1. **Configure Cluster Access**
   ```bash
   # Copy kubeconfig locally
   scp -i cluster-key.pem ubuntu@$MASTER_IP:/home/ubuntu/.kube/config ./kubeconfig
   export KUBECONFIG=./kubeconfig
   ```

2. **Install Additional Tools**
   ```bash
   # Install Helm (already installed in master)
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

   # Install additional operators, applications
   ```

3. **Configure Persistent Storage**
   - Depends on your requirements
   - Common options: EBS volumes, EFS, S3

4. **Configure Ingress**
   - Deploy ingress controller (Nginx, Traefik, etc.)
   - Configure Route53 DNS

5. **Monitor and Logging**
   - Deploy monitoring (Prometheus, etc.)
   - Deploy logging (EFK stack, etc.)

---

## Quick Reference

### Key Files and Locations

| Item | Location |
|------|----------|
| Master bootstrap script | `modules/k8s_master/userdata.sh.tpl` |
| Worker bootstrap script | `modules/k8s_worker/userdata.sh.tpl` |
| Cluster token | SSM Parameter Store: `/{project_name}/{environment}/rke2/token` |
| Master logs | `/var/log/rke2-bootstrap.log` |
| Worker logs | `/var/log/rke2-agent-bootstrap.log` |
| RKE2 config | `/etc/rancher/rke2/config.yaml` |
| kubeconfig | `/etc/rancher/rke2/rke2.yaml` or `/home/ubuntu/.kube/config` |

### Key Commands

```bash
# On Master
systemctl status rke2-server
journalctl -u rke2-server -f
kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes

# On Worker
systemctl status rke2-agent
journalctl -u rke2-agent -f

# From Local Machine
terraform output master_public_ip
terraform output worker_public_ips
ssh -i cluster-key.pem ubuntu@<instance-ip>
```

---

## Security Notes

1. **Token Management**
   - Token is stored in AWS SSM Parameter Store (SecureString)
   - Token is passed via user-data to worker nodes (within VPC, encrypted)
   - Consider rotating token after cluster is fully operational

2. **kubeconfig**
   - Stored on master instance in plain text
   - Should be copied to secure location after deployment
   - Restrict file permissions: `chmod 600 kubeconfig`

3. **Network Security**
   - Admin SSH access restricted to `admin_ssh_cidr`
   - Worker-to-master communication authenticated via RKE2 token
   - VXLAN overlay provides pod-to-pod encryption

4. **Certificate Management**
   - RKE2 automatically generates and manages certificates
   - Certificates stored in `/var/lib/rancher/rke2/server/tls/`
   - Renewal is automatic

---

## Timeline Summary

### First Deployment (Fresh Cluster)

```
Time 0:00   - terraform apply starts
Time 0:15   - Infrastructure created (VPC, SG, IAM, EC2 instances)
            - Master user-data starts executing
            - Worker user-data starts executing (in parallel)

Time 0:20   - Master RKE2 installation begins
Time 0:30   - Master RKE2 server starts initializing
Time 0:35   - Master RKE2 server becomes active
Time 0:45   - Master API responds to health checks
Time 0:50   - Master publishes token to SSM Parameter Store

Time 1:00   - Worker nodes attempt to connect to master port 9345
            - Workers retrieve token from SSM
            - Workers start RKE2 agent

Time 1:10   - All workers joined cluster
Time 1:15   - Cluster fully operational

Total Time: 15-20 minutes from terraform apply to fully operational cluster
```

---

## Assumptions and Limitations

1. **Assumes Ubuntu 22.04 LTS AMI**
   - Other Ubuntu versions may require adjustments

2. **Assumes AWS IAM permissions**
   - EC2 actions (create, modify instances)
   - SSM Parameter Store access
   - VPC/security group modifications

3. **Assumes network connectivity**
   - All instances in same VPC
   - Security groups properly configured
   - NAT/Internet Gateway for package downloads

4. **Cluster Token**
   - Token is auto-generated (random 64-character hex)
   - Can be customized in master script if needed

5. **RKE2 Version**
   - Defaults to latest stable channel
   - Can be overridden via `rke2_version` Terraform variable

---

## Support and Debugging

For detailed debugging:

1. Check Terraform state
   ```bash
   terraform state show module.k8s_master[0].aws_instance.master
   ```

2. Check AWS Systems Manager Session Manager
   ```bash
   aws ssm start-session --target i-xxxxx
   ```

3. Check CloudWatch logs (if configured)
   ```bash
   aws logs tail /aws/ec2/user-data --follow
   ```

4. Collect diagnostics from cluster
   ```bash
   kubectl get events -A
   kubectl logs -A -l component=kubelet
   ```

---

**Last Updated**: March 27, 2026
**RKE2 Version**: Stable Channel
**Terraform Version**: > 1.x
