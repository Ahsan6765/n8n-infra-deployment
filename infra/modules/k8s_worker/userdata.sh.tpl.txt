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

# ---- Check master node API readiness ----
echo "[$(date)] Checking master node API availability at ${master_private_ip}:9345..."
MASTER_READY=false
for i in $(seq 1 60); do
  if timeout 5 bash -c "echo > /dev/tcp/${master_private_ip}/9345" 2>/dev/null; then
    echo "[$(date)] Master API is reachable"
    MASTER_READY=true
    break
  fi
  echo "[$(date)] Attempt $i/60: Master not yet ready, waiting..."
  sleep 10
done

if [ "$MASTER_READY" = false ]; then
  echo "[$(date)] ERROR: Could not reach master at ${master_private_ip}:9345 after 10 minutes"
  exit 1
fi

# ---- Retrieve RKE2 join token from SSM Parameter Store ----
# Determine region reliably (use instance identity document; fall back to AZ->region)
INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region 2>/dev/null || true)
if [ -z "$INSTANCE_REGION" ]; then
  AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || true)
  # Escape the shell parameter expansion so Terraform template rendering does not try to interpolate it
  INSTANCE_REGION=$${AZ%[a-z]}
fi

echo "[$(date)] Waiting for master to publish token in SSM (region=$${INSTANCE_REGION})..."
TOKEN=""
MAX_ATTEMPTS=60  # 60 × 30 seconds = 30 minutes
for i in $(seq 1 $MAX_ATTEMPTS); do
  # Try to fetch parameter (suppress aws cli stderr to keep logs clean)
  TOKEN=$(aws ssm get-parameter \
    --name "/${project_name}/${environment}/rke2/token" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "$INSTANCE_REGION" 2>/dev/null || true)

  if [ -n "$TOKEN" ]; then
    TOKEN_LEN=$(echo -n "$TOKEN" | wc -c)
    echo "[$(date)] ✓ Token retrieved successfully from SSM (length: $TOKEN_LEN)"
    break
  fi

  if [ $i -le 3 ] || [ $((i % 6)) -eq 0 ]; then
    echo "[$(date)] Attempt $i/$MAX_ATTEMPTS: token not yet available, retrying..."
  fi
  sleep 30
done

if [ -z "$TOKEN" ]; then
  echo "[$(date)] ERROR: Could not retrieve RKE2 token from SSM after $((MAX_ATTEMPTS * 30 / 60)) minutes"
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
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${rke2_version}" INSTALL_RKE2_TYPE="agent" sh - || {
  echo "[$(date)] ERROR: Failed to download/install RKE2 agent"
  exit 1
}

# ---- Enable and start RKE2 agent ----
echo "[$(date)] Starting RKE2 agent..."
systemctl enable rke2-agent.service
systemctl start rke2-agent.service

# ---- Wait for agent to become active ----
echo "[$(date)] Waiting for RKE2 agent to initialize..."
timeout 300 bash -c 'until systemctl is-active rke2-agent &>/dev/null; do sleep 5; done' || {
  echo "[$(date)] ERROR: RKE2 agent failed to start within 5 minutes"
  journalctl -u rke2-agent -n 50
  exit 1
}

sleep 10  # Additional time for agent to register with master

# ---- Add RKE2 binaries to PATH ----
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /home/ubuntu/.bashrc

echo "[$(date)] ✓ RKE2 agent bootstrap complete"
echo "[$(date)] Worker node should be joining the cluster..."

# ---- Quick verification: check agent logs for join errors ----
echo "[$(date)] Inspecting recent rke2-agent journal entries for errors..."
journalctl -u rke2-agent -n 100 | tail -n 50 || true