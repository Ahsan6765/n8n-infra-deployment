# RKE2 Cluster Setup - Quick Reference

This is a quick reference for the two-phase cluster setup process.

## Architecture Change

The cluster setup has been refactored to separate infrastructure provisioning from cluster initialization:

```
OLD APPROACH (user_data):
Terraform → EC2 Creation → User Data Execution (long, complex, hard to debug)

NEW APPROACH (external scripts):
Terraform → EC2 Creation → [Manual] SSH → Master Setup Script → Worker Setup Scripts
```

**Benefits**:
- ✅ Better control and debugging
- ✅ Faster Terraform operations
- ✅ Easier troubleshooting
- ✅ Cleaner code
- ✅ More reliable cluster setup

---

## Directory Structure

```
project-root/
├── infra/                          # Terraform configuration
│   ├── main.tf                     # Root module orchestration
│   ├── variables.tf                # Variable definitions
│   ├── outputs.tf                  # Output definitions
│   ├── terraform.tfvars            # Variable values
│   └── modules/
│       ├── k8s_master/             # Master node module (simplified)
│       ├── k8s_worker/             # Worker node module (simplified)
│       ├── vpc/                    # VPC and networking
│       ├── security_groups/        # Security groups
│       ├── iam/                    # IAM roles
│       ├── key_pair/               # SSH key management
│       ├── s3/                     # S3 bucket for artifacts
│       └── route53/                # DNS configuration
│
├── scripts/                        # RKE2 setup scripts (NEW)
│   ├── master.sh                  # Master node initialization
│   ├── worker.sh                  # Worker node join script
│   └── CLUSTER_SETUP.md           # Detailed setup documentation
│
├── README.md                       # Project overview
└── terraform.tfstate               # Terraform state (local example)
```

---

## Quick Start

### 1. Provision Infrastructure (Terraform)

```bash
cd infra/

# Create terraform.tfvars with your configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize, plan, and apply
terraform init
terraform plan
terraform apply

# Capture outputs
terraform output -json > ../cluster-outputs.json
echo "Master IP: $(terraform output master_public_ip)"
echo "Worker IPs: $(terraform output worker_public_ips)"
```

### 2. Setup Master Node

```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>

# Transfer and run master script
# (Either copy from local or download from S3)
chmod +x master.sh
./master.sh --domain k8s.example.com --environment dev

# Capture the token for workers
cat /tmp/rke2-token.txt
```

### 3. Setup Worker Nodes

```bash
# For each worker node:
for WORKER_IP in $(terraform output -json worker_public_ips | jq -r '.[]'); do
  # SSH to worker
  ssh -i cluster-key.pem ubuntu@${WORKER_IP}
  
  # Transfer and run worker script
  chmod +x worker.sh
  ./worker.sh --master-ip <MASTER_PRIVATE_IP> --token <TOKEN>
done
```

### 4. Verify Cluster

```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>

# Check nodes
export KUBECONFIG=/home/ubuntu/.kube/config
kubectl get nodes
```

---

## Key Files

| File | Purpose |
|------|---------|
| `scripts/master.sh` | Initializes RKE2 server on master node |
| `scripts/worker.sh` | Joins worker nodes to cluster |
| `scripts/CLUSTER_SETUP.md` | Comprehensive step-by-step guide |
| `infra/main.tf` | Main Terraform configuration (no user_data) |
| `infra/modules/k8s_master/main.tf` | Master module (simplified) |
| `infra/modules/k8s_worker/main.tf` | Worker module (simplified) |
| `infra/outputs.tf` | Outputs with IP addresses and SSH commands |

---

## Important Changes from Old Setup

### Terraform Modules

**Before**: User data templates installed RKE2 automatically
- Slow terraform apply (waiting for RKE2 installation)
- Hard to debug (logs in EC2 instance only)
- Complex embedded scripts (inline bash)

**After**: No user_data, instances ready for manual setup
- Fast terraform apply (only EC2 provisioning)
- Full control over timing and debugging
- External scripts (easier to version control)

### New Outputs

Added new Terraform outputs for the new approach:
- `worker_private_ips` — For worker configuration
- `ssh_worker_commands` — Ready-to-use SSH commands for workers

### Security Groups

Security groups remain the same and already support:
- SSH (22) from admin CIDR
- RKE2 supervisor (9345) from workers to master
- Kubernetes API (6443) for kubectl access
- Kubelet (10250) for cluster communication

---

## Troubleshooting Quick Commands

```bash
# Check master is ready
ssh -i cluster-key.pem ubuntu@<MASTER_IP>
sudo systemctl status rke2-server
cat /tmp/rke2-token.txt

# Check worker is joining
ssh -i cluster-key.pem ubuntu@<WORKER_IP>
sudo systemctl status rke2-agent
sudo journalctl -u rke2-agent -n 20

# Check cluster from master
export KUBECONFIG=/home/ubuntu/.kube/config
kubectl get nodes
kubectl get pods -A
```

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Master script hangs | Check logs: `tail -f /var/log/rke2-master-setup.log` |
| Worker can't reach master | Verify master private IP, check port 9345 open |
| Invalid token error | Copy exact token from `/tmp/rke2-token.txt`, no spaces |
| Worker doesn't join | Check agent logs: `sudo journalctl -u rke2-agent -n 50` |
| kubectl timeout | Verify master API is responding: `curl -sk https://localhost:6443/healthz` |

---

## Next Steps

1. **Deploy Applications**: `kubectl apply -f app.yaml`
2. **Setup DNS**: Configure Route53 or external DNS
3. **Install Ingress**: Deploy NGINX Ingress Controller
4. **Enable Monitoring**: Install Prometheus/Grafana
5. **Configure Storage**: Setup EBS CSI Driver or similar
6. **Implement RBAC**: Create service accounts and policies

---

## Documentation

For complete setup documentation, see: [scripts/CLUSTER_SETUP.md](scripts/CLUSTER_SETUP.md)

Key sections:
- Phase 1: Infrastructure Provisioning (detailed)
- Phase 2: Cluster Initialization (detailed)
- Network Architecture diagram
- Troubleshooting guide
- Security considerations
- Scripts reference

---

## Version Info

- **Setup Approach**: External scripts (v1.0)
- **RKE2**: v1.27+ (configurable in terraform.tfvars)
- **Kubernetes**: Managed by RKE2
- **OS**: Ubuntu 22.04 LTS

---

Last Updated: 2025-01-15
