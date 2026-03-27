#!/bin/bash
# =============================================================================
# RKE2 Worker Node Setup Script
# =============================================================================
# This script sets up a RKE2 agent (worker) on an Ubuntu 22.04 instance.
# Run this script on each worker node after the master node is fully initialized.
#
# Usage: ./worker.sh --master-ip <PRIVATE_IP> --token <TOKEN> [OPTIONS]
#
# Required:
#   --master-ip <IP>           Master node private IP address
#   --token <TOKEN>            Cluster join token from master
#
# Optional:
#   --environment <env>        Environment name (default: dev)
#   --project <name>           Project name (default: n8n)
#   --rke2-version <version>   RKE2 version channel (default: stable)
#
# Example:
#   ./worker.sh --master-ip 10.0.1.10 --token "K123456789abc..." --environment prod
# =============================================================================

set -euo pipefail

# ---- Parse arguments ----
MASTER_IP=""
RKE2_TOKEN=""
ENVIRONMENT="dev"
PROJECT_NAME="n8n"
RKE2_VERSION="stable"

while [[ $# -gt 0 ]]; do
  case $1 in
    --master-ip)
      MASTER_IP="$2"
      shift 2
      ;;
    --token)
      RKE2_TOKEN="$2"
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

# ---- Validate required arguments ----
if [ -z "$MASTER_IP" ]; then
  echo "ERROR: --master-ip is required"
  echo "Usage: ./worker.sh --master-ip <IP> --token <TOKEN>"
  exit 1
fi

if [ -z "$RKE2_TOKEN" ]; then
  echo "ERROR: --token is required"
  echo "Usage: ./worker.sh --master-ip <IP> --token <TOKEN>"
  exit 1
fi

# ---- Logging ----
exec > >(tee /var/log/rke2-worker-setup.log) 2>&1
echo "[$(date)] ============================================"
echo "[$(date)] RKE2 Worker Node Setup Starting"
echo "[$(date)] Master IP: $MASTER_IP"
echo "[$(date)] Environment: $ENVIRONMENT"
echo "[$(date)] Project: $PROJECT_NAME"
echo "[$(date)] RKE2 Version: $RKE2_VERSION"
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

# ---- Retrieve instance metadata ----
echo "[$(date)] Retrieving instance metadata..."
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "[$(date)] Worker Private IP: $PRIVATE_IP"

# ---- Wait for master node to be reachable ----
echo "[$(date)] Checking master node availability at $MASTER_IP:9345..."
MAX_ATTEMPTS=60  # 60 × 10 seconds = 10 minutes
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if timeout 5 bash -c "echo > /dev/tcp/$MASTER_IP/9345" 2>/dev/null; then
    echo "[$(date)] ✓ Master node is reachable"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  echo "[$(date)] Attempt $ATTEMPT/$MAX_ATTEMPTS: Master not yet ready, retrying in 10s..."
  sleep 10
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo "[$(date)] ERROR: Could not reach master at $MASTER_IP:9345 after 10 minutes"
  exit 1
fi

# ---- Validate token format ----
echo "[$(date)] Validating cluster token..."
TOKEN_LEN=$(echo -n "$RKE2_TOKEN" | wc -c)
if [ $TOKEN_LEN -lt 40 ]; then
  echo "[$(date)] ERROR: Token appears invalid (too short: $TOKEN_LEN characters)"
  exit 1
fi

TOKEN_PREFIX=$(echo "$RKE2_TOKEN" | cut -c1-20)
echo "[$(date)] ✓ Token validated (prefix: $TOKEN_PREFIX...)"

# ---- Create RKE2 config directory ----
echo "[$(date)] Creating RKE2 config directory..."
mkdir -p /etc/rancher/rke2

# ---- Write RKE2 agent config ----
echo "[$(date)] Creating RKE2 agent configuration..."
cat > /etc/rancher/rke2/config.yaml <<EOF
# RKE2 Agent Configuration
server: https://$MASTER_IP:9345
token: "$RKE2_TOKEN"
node-label:
  - "node-role=worker"
  - "environment=$ENVIRONMENT"
  - "project=$PROJECT_NAME"
EOF

# ---- Download and install RKE2 agent ----
echo "[$(date)] Downloading and installing RKE2 agent..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="$RKE2_VERSION" INSTALL_RKE2_TYPE="agent" sh - || {
  echo "[$(date)] ERROR: Failed to download/install RKE2 agent"
  exit 1
}

# ---- Enable and start RKE2 agent ----
echo "[$(date)] Enabling and starting RKE2 agent service..."
systemctl enable rke2-agent.service
systemctl start rke2-agent.service

# ---- Wait for agent to become active ----
echo "[$(date)] Waiting for RKE2 agent to become active (timeout: 5min)..."
timeout 300 bash -c 'until systemctl is-active rke2-agent &>/dev/null; do sleep 5; done' || {
  echo "[$(date)] ERROR: RKE2 agent failed to start within 5 minutes"
  journalctl -u rke2-agent -n 50
  exit 1
}

echo "[$(date)] ✓ RKE2 agent service is active"

# ---- Wait for agent to join the cluster ----
echo "[$(date)] Waiting for agent to join the cluster (checking logs)..."
sleep 10

# ---- Verify agent is running by checking systemctl status ----
if systemctl is-active rke2-agent &>/dev/null; then
  echo "[$(date)] ✓ RKE2 agent is running"
else
  echo "[$(date)] ERROR: RKE2 agent is not running"
  journalctl -u rke2-agent -n 50
  exit 1
fi

# ---- Add RKE2 binaries to PATH ----
cat <<'EOF' >> /home/ubuntu/.bashrc
export PATH=$PATH:/var/lib/rancher/rke2/bin
EOF

# ---- Summary ----
echo "[$(date)] ============================================"
echo "[$(date)] ✓ RKE2 Worker Node Setup Complete"
echo "[$(date)] ============================================"
echo "[$(date)] "
echo "[$(date)] Worker node information:"
echo "[$(date)] - Private IP: $PRIVATE_IP"
echo "[$(date)] - Master IP: $MASTER_IP"
echo "[$(date)] - Status: Starting to join cluster"
echo "[$(date)] "
echo "[$(date)] NOTE: Worker node may take 1-2 minutes to fully join the cluster"
echo "[$(date)] "
echo "[$(date)] To verify from the master node:"
echo "[$(date)]   export KUBECONFIG=/home/ubuntu/.kube/config"
echo "[$(date)]   kubectl get nodes"
echo "[$(date)] "
echo "[$(date)] This worker should appear in the ready state shortly"
echo "[$(date)] "
