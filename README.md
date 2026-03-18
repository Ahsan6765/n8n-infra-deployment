# AWS Kubernetes Cluster – Terraform Infrastructure

Production-ready Terraform project that provisions AWS infrastructure for a **Kubernetes cluster using RKE2** with 1 master node and 3 worker nodes.

---

## Architecture

```
n8n-infra-deployment/
├── backend.tf                   # S3 + DynamoDB remote state
├── main.tf                      # Root orchestration
├── variables.tf                 # All configurable inputs
├── outputs.tf                   # Key infrastructure outputs
├── versions.tf                  # Provider version constraints
├── terraform.tfvars.example     # Copy → terraform.tfvars and fill in
└── modules/
    ├── s3/              # Terraform state bucket + artifact bucket + DynamoDB lock
    ├── iam/             # EC2 node IAM role, policy, instance profile
    ├── key_pair/        # SSH key pair
    ├── vpc/             # VPC, public subnets (3 AZs), IGW, route tables
    ├── security_groups/ # Master SG + Worker SG (port-level + SG-to-SG rules)
    ├── k8s_master/      # EC2 master instance + EIP + RKE2 server user-data
    ├── k8s_worker/      # 3 × EC2 worker instances + RKE2 agent user-data
    └── route53/         # Hosted zone + API/wildcard DNS records
```

### AWS Resources Provisioned

| Resource            | Details                                                             |
| ------------------- | ------------------------------------------------------------------- |
| **EC2 (Master)**    | 1 × Ubuntu 22.04, `t3.medium`, RKE2 server, Elastic IP              |
| **EC2 (Workers)**   | 3 × Ubuntu 22.04, `t3.medium`, RKE2 agent                           |
| **VPC**             | `/16` CIDR, 3 public subnets across AZs                             |
| **Security Groups** | Master SG (API 6443, etcd, kubelet) · Worker SG (NodePort, kubelet) |
| **IAM Role**        | EC2 node role – EC2/ELB/S3/SSM permissions                          |
| **Key Pair**        | SSH key pair (auto-generated or user-supplied)                      |
| **S3 Buckets**      | State bucket (versioned, AES256) · Artifact bucket                  |
| **DynamoDB**        | State lock table                                                    |
| **Route 53**        | Hosted zone · `k8s.<domain>` · `*.k8s.<domain>`                     |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.6
- AWS CLI configured with credentials (`aws configure` or environment variables)
- An AWS account with permissions to create all resources above

---

## Quick Start

### Step 1 – Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### Step 2 – Bootstrap the S3 state backend

The state bucket must exist before activating the backend. Use local state first:

```bash
# Comment out the `terraform { backend "s3" { ... } }` block in backend.tf
terraform init
terraform apply -target=module.s3
```

Then:

1. Note the bucket name from `terraform output state_bucket_name`
2. Update `backend.tf` with the actual bucket name
3. Un-comment the backend block
4. Migrate state: `terraform init -migrate-state`

### Step 3 – Full deployment

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 4 – Verify cluster

```bash
# SSH to master (key auto-saved to cluster-key.pem)
ssh -i cluster-key.pem ubuntu@$(terraform output -raw master_public_ip)

# On the master:
kubectl get nodes
# Expected: 1 master + 3 workers in Ready state
```

---

## Key Variables

| Variable               | Default           | Description                              |
| ---------------------- | ----------------- | ---------------------------------------- |
| `aws_region`           | `us-east-1`       | AWS deployment region                    |
| `master_instance_type` | `t3.medium`       | Master EC2 instance type                 |
| `worker_instance_type` | `t3.medium`       | Worker EC2 instance type                 |
| `worker_count`         | `3`               | Number of worker nodes                   |
| `rke2_version`         | `v1.29`           | RKE2 release channel                     |
| `domain_name`          | `k8s.example.com` | Route 53 domain                          |
| `admin_ssh_cidr`       | `0.0.0.0/0`       | SSH access CIDR (tighten in production!) |

See [`variables.tf`](./variables.tf) for the full list.

---

## Security Notes

- ⚠️ Set `admin_ssh_cidr` to your specific IP in production (not `0.0.0.0/0`)
- RKE2 join token is stored as a `SecureString` in SSM Parameter Store
- All EBS volumes are encrypted with AES-256
- S3 buckets block all public access
- IAM uses least-privilege inline policies

---

## Destroy

```bash
terraform destroy
```

---

## Module Outputs

After `terraform apply`:

| Output               | Description                   |
| -------------------- | ----------------------------- |
| `master_public_ip`   | Elastic IP of the master node |
| `worker_public_ips`  | List of worker public IPs     |
| `kubernetes_api_dns` | `k8s.<domain>` DNS name       |
| `ssh_master_command` | Ready-to-use SSH command      |
| `state_bucket_name`  | Actual S3 state bucket name   |
