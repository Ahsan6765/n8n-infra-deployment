#!/bin/bash
# =============================================================================
# RKE2 Agent (Worker) Bootstrap Script
# User-data template for Kubernetes worker nodes
# =============================================================================
set -euo pipefail

# ---- Logging ----
exec > >(tee /var/log/rke2-agent-bootstrap.log) 2>&1
echo "[$(date)] Starting RKE2 agent bootstrap..."

# ---- System prerequisites ----
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget git jq awscli

# ---- Disable swap ----
swapoff -a
sed -i '/swap/d' /etc/fstab

# ---- Kernel parameters ----
cat <<'EOF' > /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                  = 1
EOF
sysctl --system

# ---- Load kernel modules ----
modprobe overlay
modprobe br_netfilter
cat <<'EOF' >> /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# ---- Retrieve RKE2 join token from SSM Parameter Store ----
INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

echo "[$(date)] Waiting for master to publish token..."
TOKEN=""
for i in $(seq 1 30); do
  TOKEN=$(aws ssm get-parameter \
    --name "/${project_name}/${environment}/rke2/token" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "$INSTANCE_REGION" 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then
    echo "[$(date)] Token retrieved successfully."
    break
  fi
  echo "[$(date)] Attempt $i: token not yet available, retrying in 20s..."
  sleep 20
done

if [ -z "$TOKEN" ]; then
  echo "[$(date)] ERROR: Could not retrieve RKE2 token after 10 minutes. Exiting."
  exit 1
fi

# ---- Worker node index from instance tags ----
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# ---- Create RKE2 config directory ----
mkdir -p /etc/rancher/rke2

# ---- Write RKE2 agent config ----
cat <<EOF > /etc/rancher/rke2/config.yaml
# RKE2 Agent Configuration
server: https://${master_private_ip}:9345
token: "$TOKEN"
node-label:
  - "node-role=worker"
  - "environment=${environment}"
  - "project=${project_name}"
EOF

# ---- Download and install RKE2 agent ----
echo "[$(date)] Downloading RKE2 agent installer..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${rke2_version}" INSTALL_RKE2_TYPE="agent" sh -

# ---- Enable and start RKE2 agent ----
systemctl enable rke2-agent.service
systemctl start rke2-agent.service

# ---- Wait for agent to start ----
echo "[$(date)] Waiting for RKE2 agent to initialize..."
timeout 180 bash -c 'until systemctl is-active rke2-agent &>/dev/null; do sleep 5; done'

# ---- Add RKE2 binaries to PATH ----
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /home/ubuntu/.bashrc

echo "[$(date)] RKE2 agent bootstrap complete. Worker node joined the cluster."
