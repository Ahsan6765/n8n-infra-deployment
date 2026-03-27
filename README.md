# n8n RKE2 Cluster Provisioning (Terraform + Scripts)

This repository provisions infrastructure with Terraform and configures an RKE2 Kubernetes cluster using external scripts for reliability and debuggability.

Overview
 - Terraform provisions VPC, security groups, EC2 instances (master and workers), and IAM resources.
 - Cluster bootstrap is performed manually (or via automation) using scripts in the `infra/scripts/` directory.

Why this approach?
 - Avoids embedding large user-data scripts in Terraform templates
 - Easier to debug and iterate on cluster installation
 - Gives operators explicit control over bootstrap order

Quick start
1. Provision infrastructure with Terraform (from `infra/`):

```bash
cd infra
terraform init
terraform apply -auto-approve
```

2. Note the master public IP and worker public IPs from Terraform outputs:

```bash
terraform output master_public_ip
terraform output worker_public_ips
```

3. SSH to the master and run the master script (as root):

```bash
# from repository root
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>
sudo bash -s < infra/scripts/master.sh
```

4. Retrieve the token from the master:

```bash
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>
sudo cat /home/ubuntu/rke2-node-token
```

5. Run `worker.sh` on each worker, passing the master private IP and token:

```bash
# from repository root
ssh -i cluster-key.pem ubuntu@<WORKER_PUBLIC_IP>
sudo bash -s -- < infra/scripts/worker.sh > <MASTER_PRIVATE_IP> <TOKEN>
```

6. Verify cluster on master:

```bash
ssh -i cluster-key.pem ubuntu@<MASTER_PUBLIC_IP>
sudo su - ubuntu
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes
```

Notes
 - Ensure security groups allow SSH, 6443 and 9345 between master and workers.
 - The scripts are intentionally simple; modify as needed for your environment.

Helper scripts available in `infra/scripts/`:

- `bootstrap-cluster.sh` — automates running `master.sh` and `worker.sh` using Terraform outputs and the generated key.
- `recreate-workers.sh` — taints and recreates worker EC2 instances so they pick up updated userdata/config.
