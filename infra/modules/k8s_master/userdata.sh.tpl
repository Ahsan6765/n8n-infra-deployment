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

# ---- Generate a random cluster token (or use a pre-shared one) ----
RKE2_TOKEN=$(openssl rand -hex 32)
echo "$RKE2_TOKEN" > /var/lib/rancher/rke2/server/node-token.staging
mkdir -p /var/lib/rancher/rke2/server

# ---- Write RKE2 server config ----
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
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${rke2_version}" sh -

# ---- Enable and start RKE2 server ----
systemctl enable rke2-server.service
systemctl start rke2-server.service

# ---- Wait for RKE2 to become ready ----
echo "[$(date)] Waiting for RKE2 server to initialize..."
timeout 300 bash -c 'until systemctl is-active rke2-server &>/dev/null; do sleep 5; done'
sleep 30  # Additional stabilization time

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

aws ssm put-parameter \
  --name "/${project_name}/${environment}/rke2/token" \
  --value "$RKE2_TOKEN" \
  --type "SecureString" \
  --overwrite \
  --region "$INSTANCE_REGION" || true

echo "[$(date)] RKE2 master bootstrap complete."
echo "[$(date)] Token stored in SSM: /${project_name}/${environment}/rke2/token"
