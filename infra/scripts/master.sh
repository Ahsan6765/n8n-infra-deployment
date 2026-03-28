#!/bin/bash
# =============================================================================
# RKE2 Master Node Setup Script
# =============================================================================
# This script sets up a RKE2 server (master) on an Ubuntu 22.04 instance.
# Run this script on the master node immediately after instance creation.
#
# Usage: ./master.sh [OPTIONS]
# Options:
#   --domain <domain>          Domain name for RKE2 TLS SAN (default: none)
#   --environment <env>        Environment name (default: dev)
#   --project <name>           Project name (default: n8n)
#   --rke2-version <version>   RKE2 version channel (default: stable)
#
# Example:
#   ./master.sh --domain k8s.example.com --environment prod --project n8n
# =============================================================================

set -euo pipefail

# ---- Parse arguments ----
DOMAIN_NAME="${1:-}"
ENVIRONMENT="dev"
PROJECT_NAME="n8n"
RKE2_VERSION="stable"

while [[ $# -gt 0 ]]; do
  case $1 in
    --domain)
      DOMAIN_NAME="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --project)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --rke2-version)
      RKE2_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---- Logging ----
exec > >(tee /var/log/rke2-master-setup.log) 2>&1
echo "[$(date)] ============================================"
echo "[$(date)] RKE2 Master Node Setup Starting"
echo "[$(date)] Environment: $ENVIRONMENT"
echo "[$(date)] Project: $PROJECT_NAME"
echo "[$(date)] RKE2 Version: $RKE2_VERSION"
if [ -n "$DOMAIN_NAME" ]; then
  echo "[$(date)] Domain: $DOMAIN_NAME"
fi
echo "[$(date)] ============================================"

# ---- System prerequisites ----
echo "[$(date)] Installing system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget git jq awscli

# ---- Disable swap (required by Kubernetes) ----
echo "[$(date)] Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# ---- Set kernel parameters for Kubernetes networking ----
echo "[$(date)] Configuring kernel parameters..."
cat <<'EOF' > /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                  = 1
EOF
sysctl --system

# ---- Load overlay and br_netfilter kernel modules ----
echo "[$(date)] Loading kernel modules..."
modprobe overlay
modprobe br_netfilter
cat <<'EOF' >> /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# ---- Create RKE2 config directory ----
echo "[$(date)] Creating RKE2 config directory..."
mkdir -p /etc/rancher/rke2

# ---- Retrieve instance metadata ----
echo "[$(date)] Retrieving instance metadata..."
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "[$(date)] Public IP: $PUBLIC_IP"
echo "[$(date)] Private IP: $PRIVATE_IP"

# ---- Write RKE2 server config ----
echo "[$(date)] Creating RKE2 server configuration..."
cat > /etc/rancher/rke2/config.yaml <<EOF
# RKE2 Server Configuration
write-kubeconfig-mode: "0644"
tls-san:
  - "$PUBLIC_IP"
  - "$PRIVATE_IP"
$([ -n "$DOMAIN_NAME" ] && echo "  - \"$DOMAIN_NAME\"" || true)
cluster-cidr: "10.42.0.0/16"
service-cidr: "10.43.0.0/16"
cni: canal
node-label:
  - "node-role=master"
  - "environment=$ENVIRONMENT"
  - "project=$PROJECT_NAME"
EOF

# ---- Download and install RKE2 ----
echo "[$(date)] Downloading and installing RKE2 server..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="$RKE2_VERSION" sh - || {
  echo "[$(date)] ERROR: Failed to download/install RKE2"
  exit 1
}

# ---- Enable and start RKE2 server ----
echo "[$(date)] Enabling and starting RKE2 server service..."
systemctl enable rke2-server.service
systemctl start rke2-server.service

# ---- Wait for RKE2 service to be active ----
echo "[$(date)] Waiting for RKE2 server service to become active (timeout: 5min)..."
timeout 300 bash -c 'until systemctl is-active rke2-server &>/dev/null; do sleep 5; done' || {
  echo "[$(date)] ERROR: RKE2 server failed to start within 5 minutes"
  journalctl -u rke2-server -n 50
  exit 1
}

echo "[$(date)] ✓ RKE2 server service is active"

# ---- Wait for RKE2 API to be responsive ----
echo "[$(date)] Waiting for RKE2 API to be ready (timeout: 5min)..."
timeout 300 bash -c '
  until curl -sk https://localhost:6443/healthz &>/dev/null; do
    sleep 5
  done
' || {
  echo "[$(date)] WARNING: API health check failed, but continuing..."
}

sleep 15  # Additional time for cluster stabilization
echo "[$(date)] ✓ RKE2 API is ready"

# ---- Verify node-token file exists ----
echo "[$(date)] Waiting for RKE2 node-token file to be created..."
timeout 60 bash -c 'until [ -f /var/lib/rancher/rke2/server/node-token ]; do sleep 5; done' || {
  echo "[$(date)] ERROR: RKE2 did not create node-token file"
  exit 1
}

sleep 5
echo "[$(date)] ✓ Node-token file created"

# ---- Read the RKE2 token ----
echo "[$(date)] Reading RKE2 cluster token..."
NODE_TOKEN=$(cat /var/lib/rancher/rke2/server/node-token)

if [ -z "$NODE_TOKEN" ] || [ $(echo -n "$NODE_TOKEN" | wc -c) -lt 40 ]; then
  echo "[$(date)] ERROR: Node-token file missing or token too short"
  exit 1
fi

TOKEN_PREFIX=$(echo "$NODE_TOKEN" | cut -c1-20)
echo "[$(date)] ✓ Token verified (prefix: $TOKEN_PREFIX...)"

# ---- Setup kubectl for ubuntu user ----
echo "[$(date)] Configuring kubectl for ubuntu user..."
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/rke2/rke2.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# ---- Add RKE2 binaries to PATH ----
cat <<'EOF' >> /home/ubuntu/.bashrc
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/home/ubuntu/.kube/config
EOF

# ---- Create symlinks for convenience ----
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl

# ---- Save token and config to files for easy export ----
echo "[$(date)] Saving token and configuration to files..."
cat > /tmp/rke2-token.txt <<EOF
$NODE_TOKEN
EOF
chmod 644 /tmp/rke2-token.txt
chown ubuntu:ubuntu /tmp/rke2-token.txt

cat > /tmp/rke2-cluster-info.txt <<EOF
Master Setup Summary
====================
Master Private IP: $PRIVATE_IP
Master Public IP: $PUBLIC_IP
Cluster Token saved in: /tmp/rke2-token.txt

Configuration:
- Cluster CIDR: 10.42.0.0/16
- Service CIDR: 10.43.0.0/16
- Flannel CNI: enabled

To join worker nodes:
1. Run the worker script on each worker node with:
   ./worker.sh --master-ip $PRIVATE_IP --token \$(cat /tmp/rke2-token.txt)

To access the cluster:
  export KUBECONFIG=/home/ubuntu/.kube/config
  kubectl get nodes

Cluster startup log:
  tail -f /var/log/rke2-master-setup.log
EOF

echo "[$(date)] ============================================"
echo "[$(date)] ✓ RKE2 Master Node Setup Complete"
echo "[$(date)] ============================================"
echo "[$(date)] "
echo "[$(date)] Token has been saved to: /tmp/rke2-token.txt"
echo "[$(date)] Cluster info saved to: /tmp/rke2-cluster-info.txt"
echo "[$(date)] "
echo "[$(date)] NEXT STEPS:"
echo "[$(date)] 1. Copy the token from this master:"
echo "[$(date)] 2. Run worker.sh on each worker node with the token and master IP"
echo "[$(date)] 3. Worker will automatically join the cluster"
echo "[$(date)] "
echo "[$(date)] Check cluster status:"
echo "[$(date)] export KUBECONFIG=/home/ubuntu/.kube/config && kubectl get nodes"
echo "[$(date)] "
