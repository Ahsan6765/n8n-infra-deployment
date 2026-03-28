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

# ---- Logging Setup ----
LOG_FILE="/var/log/rke2-worker-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

log_warn() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $1"
}

log_debug() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $1"
}

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
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ---- Validate required arguments ----
if [ -z "$MASTER_IP" ]; then
  log_error "Missing required argument: --master-ip"
  log_error "Usage: ./worker.sh --master-ip <IP> --token <TOKEN> [OPTIONS]"
  exit 1
fi

if [ -z "$RKE2_TOKEN" ]; then
  log_error "Missing required argument: --token"
  log_error "Usage: ./worker.sh --master-ip <IP> --token <TOKEN>"
  exit 1
fi

log_info "=========================================="
log_info "RKE2 Worker Node Setup Starting"
log_info "=========================================="
log_info "Master IP: $MASTER_IP"
log_info "Environment: $ENVIRONMENT"
log_info "Project: $PROJECT_NAME"
log_info "RKE2 Version: $RKE2_VERSION"
log_info "Log File: $LOG_FILE"
log_info "=========================================="

# ---- Validate we're running with proper privileges ----
if [[ $EUID -ne 0 ]]; then
  log_error "This script requires elevated privileges (root/sudo)"
  exit 1
fi

log_info "✓ Running with root privileges"

# ---- System prerequisites ----
log_info "Installing system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y > /dev/null 2>&1 || log_warn "apt-get update had issues"
apt-get install -y curl wget git jq awscli > /dev/null 2>&1 || log_warn "Some packages may not be installed"
log_info "✓ System packages installed"

# ---- Disable swap (required by Kubernetes) ----
log_info "Disabling swap..."
swapoff -a || log_warn "Could not swapoff (may not have swap)"
sed -i '/swap/d' /etc/fstab || log_warn "Could not update fstab"
log_info "✓ Swap disabled"

# ---- Set kernel parameters for Kubernetes networking ----
log_info "Configuring kernel parameters..."
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                  = 1
EOF
sysctl --system > /dev/null 2>&1 || log_warn "sysctl configuration had issues"
log_info "✓ Kernel parameters configured"

# ---- Load overlay and br_netfilter kernel modules ----
log_info "Loading kernel modules..."
modprobe overlay || log_warn "Could not load overlay module"
modprobe br_netfilter || log_warn "Could not load br_netfilter module"
mkdir -p /etc/modules-load.d
cat >> /etc/modules-load.d/containerd.conf <<'EOF'
overlay
br_netfilter
EOF
log_info "✓ Kernel modules loaded"

# ---- Retrieve instance metadata ----
log_info "Retrieving instance metadata..."
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "UNKNOWN")
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "UNKNOWN")
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "UNKNOWN")
log_info "✓ Instance metadata retrieved"
log_info "  - Private IP: $PRIVATE_IP"
log_info "  - Instance ID: $INSTANCE_ID"
log_info "  - Availability Zone: $AVAILABILITY_ZONE"

# ---- Wait for master node to be reachable (TCP port 9345) ----
log_info "Checking master node API availability at $MASTER_IP:9345..."
MAX_ATTEMPTS=60
ATTEMPT=0
MASTER_READY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if timeout 5 bash -c "echo > /dev/tcp/$MASTER_IP/9345" 2>/dev/null; then
    log_info "✓ Master node is reachable at $MASTER_IP:9345"
    MASTER_READY=true
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  
  # Log less frequently to reduce noise
  if [ $((ATTEMPT % 6)) -eq 0 ] || [ $ATTEMPT -le 3 ]; then
    log_info "  Attempt $ATTEMPT/$MAX_ATTEMPTS: Master not yet ready (retrying in 10s)"
  fi
  
  sleep 10
done

if [ "$MASTER_READY" = false ]; then
  log_error "Could not reach master at $MASTER_IP:9345 after 10 minutes"
  log_error ""
  log_error "Possible causes:"
  log_error "  1. Master node is not running or still initializing"
  log_error "  2. Security group does not allow port 9345 from worker"
  log_error "  3. Network connectivity issue between worker and master"
  log_error "  4. Master IP address is incorrect (got: $MASTER_IP)"
  log_error "  5. RKE2 master service failed to start"
  log_error ""
  log_error "Debugging steps:"
  log_error "  - Verify master instance is running"
  log_error "  - Check master security group inbound rules for port 9345"
  log_error "  - From master, run: systemctl status rke2-server"
  log_error "  - From master, check: journalctl -u rke2-server | head -50"
  exit 1
fi

# ---- Validate token format ----
log_info "Validating cluster token..."
TOKEN_LEN=${#RKE2_TOKEN}

if [ "$TOKEN_LEN" -lt 10 ]; then
  log_error "Token appears invalid (too short: $TOKEN_LEN characters)"
  log_error "Expected minimum length: 40 characters"
  exit 1
fi

if [ "$TOKEN_LEN" -lt 40 ]; then
  log_warn "Token is shorter than expected ($TOKEN_LEN chars), but continuing..."
fi

TOKEN_PREFIX=$(echo "$RKE2_TOKEN" | cut -c1-15)
log_info "✓ Token validated (length: $TOKEN_LEN characters, prefix: ${TOKEN_PREFIX}...)"

# ---- Create RKE2 config directory ----
log_info "Creating RKE2 config directory..."
mkdir -p /etc/rancher/rke2 || {
  log_error "Failed to create /etc/rancher/rke2 directory"
  exit 1
}
log_info "✓ RKE2 config directory created"

# ---- Write RKE2 agent config ----
log_info "Creating RKE2 agent configuration file..."
cat > /etc/rancher/rke2/config.yaml <<EOF
# RKE2 Agent Configuration
# Generated: $(date)
server: https://$MASTER_IP:9345
token: "$RKE2_TOKEN"
node-label:
  - "node-role=worker"
  - "environment=$ENVIRONMENT"
  - "project=$PROJECT_NAME"
EOF

if [ ! -f /etc/rancher/rke2/config.yaml ]; then
  log_error "Failed to create RKE2 config file at /etc/rancher/rke2/config.yaml"
  exit 1
fi

log_info "✓ RKE2 agent configuration file created"
log_debug "Config file location: /etc/rancher/rke2/config.yaml"

# ---- Download and install RKE2 agent ----
log_info "Downloading RKE2 agent installer (channel: $RKE2_VERSION)..."
if ! curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="$RKE2_VERSION" INSTALL_RKE2_TYPE="agent" sh - 2>&1 | tee -a "$LOG_FILE"; then
  log_error "Failed to download or install RKE2 agent"
  log_error ""
  log_error "Possible causes:"
  log_error "  - Network connectivity issue (cannot reach get.rke2.io)"
  log_error "  - Invalid RKE2 version channel: $RKE2_VERSION"
  log_error "  - Insufficient disk space"
  log_error "  - Package manager issues"
  log_error ""
  log_error "Check network connectivity: curl -v https://get.rke2.io"
  exit 1
fi
log_info "✓ RKE2 agent installed successfully"

# ---- Enable and start RKE2 agent ----
log_info "Enabling and starting RKE2 agent service..."
systemctl daemon-reload || log_warn "systemctl daemon-reload encountered issues"
systemctl enable rke2-agent.service || {
  log_error "Failed to enable rke2-agent service"
  exit 1
}

log_debug "Starting rke2-agent service..."
if ! systemctl start rke2-agent.service 2>&1 | tee -a "$LOG_FILE"; then
  log_error "Failed to start rke2-agent service"
  log_error ""
  log_error "Service status:"
  systemctl status rke2-agent.service 2>&1 | tee -a "$LOG_FILE" || true
  exit 1
fi

log_info "✓ RKE2 agent service started"

# ---- Wait for agent to become active ----
log_info "Waiting for RKE2 agent to initialize (up to 5 minutes)..."
if ! timeout 300 bash -c 'until systemctl is-active rke2-agent &>/dev/null; do sleep 5; done' 2>/dev/null; then
  log_error "RKE2 agent failed to start within 5 minutes"
  log_error ""
  log_error "Recent service logs:"
  journalctl -u rke2-agent -n 50 2>&1 | tee -a "$LOG_FILE" || true
  log_error ""
  log_error "Troubleshooting:"
  log_error "  1. Check if service started: systemctl status rke2-agent"
  log_error "  2. View agent logs: journalctl -u rke2-agent -f"
  log_error "  3. Check master connectivity: telnet $MASTER_IP 9345"
  exit 1
fi

log_info "✓ RKE2 agent service is active"

# ---- Wait a bit longer for agent to register with cluster ----
log_info "Waiting for agent to register with cluster (30 seconds)..."
sleep 30

# ---- Verify agent is still running ----
if ! systemctl is-active rke2-agent &>/dev/null; then
  log_error "RKE2 agent is no longer running after initialization"
  log_error ""
  log_error "Recent service logs:"
  journalctl -u rke2-agent -n 50 2>&1 | tee -a "$LOG_FILE" || true
  exit 1
fi

log_info "✓ RKE2 agent is still running"

# ---- Add RKE2 binaries to PATH for ubuntu user ----
log_info "Configuring PATH for RKE2 binaries..."
BASHRC_PATH="/home/ubuntu/.bashrc"
if [ -f "$BASHRC_PATH" ]; then
  if ! grep -q "/var/lib/rancher/rke2/bin" "$BASHRC_PATH" 2>/dev/null; then
    cat <<'EOF' >> "$BASHRC_PATH"

# RKE2 binaries PATH
export PATH=$PATH:/var/lib/rancher/rke2/bin
EOF
    log_info "✓ Updated PATH in /home/ubuntu/.bashrc"
  else
    log_info "✓ PATH already configured in /home/ubuntu/.bashrc"
  fi
else
  log_warn "Could not find /home/ubuntu/.bashrc (non-critical)"
fi

# ---- Final validation and logging ----
log_info "=========================================="
log_info "✓ RKE2 Worker Node Setup Complete"
log_info "=========================================="
log_info ""
log_info "Worker node information:"
log_info "  - Private IP: $PRIVATE_IP"
log_info "  - Master IP: $MASTER_IP"
log_info "  - Environment: $ENVIRONMENT"
log_info "  - Project: $PROJECT_NAME"
log_info "  - Status: Joining cluster..."
log_info ""
log_info "Next steps:"
log_info "  1. Wait 1-2 minutes for the node to fully join the cluster"
log_info "  2. From the master node, run:"
log_info "       export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
log_info "       kubectl get nodes"
log_info "  3. This worker should appear in the output shortly"
log_info ""
log_info "Troubleshooting:"
log_info "  If the node doesn't appear after 5 minutes:"
log_info "    - Check this log file: $LOG_FILE"
log_info "    - Check RKE2 agent status: systemctl status rke2-agent"
log_info "    - View agent logs: journalctl -u rke2-agent -f"
log_info "    - Verify network connectivity to master:"
log_info "        ping $MASTER_IP"
log_info "        telnet $MASTER_IP 9345"
log_info "    - From master, check cluster status:"
log_info "        export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
log_info "        kubectl describe node $(hostname)"
log_info "=========================================="
log_info ""
log_info "Setup completed successfully at $(date)"
