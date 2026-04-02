#!/bin/bash
# =============================================================================
# RKE2 Server (Master) Bootstrap Script
# User-data template for the Kubernetes master node
# =============================================================================
set -euo pipefail

# ---- Logging ----
exec > >(tee /var/log/rke2-bootstrap.log) 2>&1
echo "[$(date)] Starting RKE2 master bootstrap..."

# ---- System prerequisites ----
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget git jq awscli

# ---- Disable swap (required by Kubernetes) ----
swapoff -a
sed -i '/swap/d' /etc/fstab

# ---- Set kernel parameters for Kubernetes networking ----
cat <<'EOF' > /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                  = 1
EOF
sysctl --system

# ---- Load overlay and br_netfilter kernel modules ----
modprobe overlay
modprobe br_netfilter
cat <<'EOF' >> /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# ---- Create RKE2 config directory ----
mkdir -p /etc/rancher/rke2

# ---- Generate a pre-shared cluster token ----
RKE2_TOKEN=$(openssl rand -hex 32)
echo "[$(date)] Generated cluster token: $RKE2_TOKEN"
mkdir -p /var/lib/rancher/rke2/server

# ---- Write RKE2 server config with the token ----
cat <<EOF > /etc/rancher/rke2/config.yaml
# RKE2 Server Configuration
write-kubeconfig-mode: "0644"
token: "$RKE2_TOKEN"
tls-san:
  - "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
  - "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
  - "${domain_name}"
cluster-cidr: "10.42.0.0/16"
service-cidr: "10.43.0.0/16"
cni: canal
node-label:
  - "node-role=master"
  - "environment=${environment}"
  - "project=${project_name}"
EOF

# ---- Download and install RKE2 ----
echo "[$(date)] Downloading RKE2 installer..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${rke2_version}" sh - || {
  echo "[$(date)] ERROR: Failed to download/install RKE2"
  exit 1
}

# ---- Enable and start RKE2 server ----
echo "[$(date)] Starting RKE2 server..."
systemctl enable rke2-server.service
systemctl start rke2-server.service

# ---- Wait for RKE2 service to be active ----
echo "[$(date)] Waiting for RKE2 server service to become active..."
timeout 300 bash -c 'until systemctl is-active rke2-server &>/dev/null; do sleep 5; done' || {
  echo "[$(date)] ERROR: RKE2 server failed to start within 5 minutes"
  journalctl -u rke2-server -n 50
  exit 1
}

echo "[$(date)] RKE2 server service is active. Waiting for API to be ready..."

# ---- Wait for RKE2 API to be responsive ----
timeout 300 bash -c '
  until curl -sk https://localhost:6443/healthz &>/dev/null; do
    sleep 5
  done
' || {
  echo "[$(date)] WARNING: API health check failed, but continuing..."
}

sleep 15  # Additional time for cluster stabilization

# ---- Wait for RKE2 supervisor port (9345) which workers use to join ----
echo "[$(date)] Waiting for RKE2 supervisor port 9345 to be ready..."
timeout 300 bash -c '
  until timeout 5 bash -c "echo > /dev/tcp/localhost/9345" 2>/dev/null; do
    sleep 5
  done
' || {
  echo "[$(date)] ERROR: RKE2 supervisor port 9345 not ready after 5 minutes"
  journalctl -u rke2-server -n 50
  exit 1
}

sleep 10

# ---- Verify node-token file was created by RKE2 ----
if [ ! -f /var/lib/rancher/rke2/server/node-token ]; then
  echo "[$(date)] ERROR: RKE2 did not create node-token file"
  exit 1
fi

# ---- Read the actual RKE2 token (should match what we configured) ----
ACTUAL_TOKEN=$(cat /var/lib/rancher/rke2/server/node-token)

# Validate token format and length before storing
if [ -z "$ACTUAL_TOKEN" ] || [ $(echo -n "$ACTUAL_TOKEN" | wc -c) -lt 40 ]; then
  echo "[$(date)] ERROR: Node-token file missing or token too short"
  exit 1
fi

if ! echo "$ACTUAL_TOKEN" | grep -qE '^[A-Za-z0-9:+/=._-]{10,}$'; then
  # don't expose full token in logs; print a prefix
  echo "[$(date)] ERROR: Token format looks invalid"
  exit 1
fi

PREFIX=$(echo "$ACTUAL_TOKEN" | cut -c1-20)
echo "[$(date)] Verified token in RKE2 (prefix): $PREFIX..."

# ---- Setup kubectl for ubuntu user ----
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/rke2/rke2.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# ---- Add RKE2 binaries to PATH ----
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /home/ubuntu/.bashrc
echo 'export KUBECONFIG=/home/ubuntu/.kube/config' >> /home/ubuntu/.bashrc

# ---- Create symlinks for convenience ----
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl

# ---- Store token in SSM Parameter Store for worker nodes ----
INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

echo "[$(date)] Storing token in SSM Parameter Store..."
aws ssm put-parameter \
  --name "/${project_name}/${environment}/rke2/token" \
  --value "$ACTUAL_TOKEN" \
  --type "SecureString" \
  --overwrite \
  --region "$INSTANCE_REGION" || {
  echo "[$(date)] ERROR: Failed to store token in SSM Parameter Store"
  exit 1
}

# ---- Verify token was stored in SSM ----
STORED_TOKEN=$(aws ssm get-parameter \
  --name "/${project_name}/${environment}/rke2/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "$INSTANCE_REGION" 2>/dev/null || echo "")

if [ "$STORED_TOKEN" != "$ACTUAL_TOKEN" ]; then
  echo "[$(date)] ERROR: Token verification failed. SSM token doesn't match RKE2 token"
  exit 1
fi

echo "[$(date)] ✓ Token successfully stored and verified in SSM"
echo "[$(date)] ✓ RKE2 master bootstrap complete"
echo "[$(date)] Master node ready. Workers can now join the cluster."
