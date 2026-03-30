#!/bin/bash
# =============================================================================
# RKE2 Worker Node Setup Script
# =============================================================================
set -e
set -o pipefail

LOG_FILE="/var/log/rke2-worker-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

# ---- Parse named arguments ----
MASTER_IP=""
RKE2_TOKEN=""
TOKEN_FILE=""
ENVIRONMENT="dev"
PROJECT_NAME="n8n"
RKE2_VERSION="stable"

while [[ $# -gt 0 ]]; do
  case $1 in
    --master-ip)    MASTER_IP="$2";    shift 2 ;;
    --token)        RKE2_TOKEN="$2";   shift 2 ;;
    --token-file)   TOKEN_FILE="$2";   shift 2 ;;
    --environment)  ENVIRONMENT="$2";  shift 2 ;;
    --project)      PROJECT_NAME="$2"; shift 2 ;;
    --rke2-version) RKE2_VERSION="$2"; shift 2 ;;
    *) log "Unknown argument: $1"; exit 1 ;;
  esac
done

# ---- Read token from file if token-file specified ----
if [ -n "$TOKEN_FILE" ] && [ -f "$TOKEN_FILE" ]; then
  log "Reading token from file: $TOKEN_FILE"
  RKE2_TOKEN=$(cat "$TOKEN_FILE")
  # Remove token file immediately after reading for security
  rm -f "$TOKEN_FILE"
fi

# ---- Validate required args ----
if [ -z "$MASTER_IP" ]; then
  log "ERROR: --master-ip is required"
  exit 1
fi
if [ -z "$RKE2_TOKEN" ]; then
  log "ERROR: --token or --token-file is required"
  exit 1
fi

log "=========================================="
log "RKE2 Worker Node Setup Starting"
log "Master IP:   $MASTER_IP"
log "Token length: ${#RKE2_TOKEN}"
log "Environment: $ENVIRONMENT"
log "Project:     $PROJECT_NAME"
log "RKE2 Ver:   $RKE2_VERSION"
log "=========================================="

# ---- Root check ----
if [[ $EUID -ne 0 ]]; then
  log "ERROR: Must run as root"
  exit 1
fi

# ---- System prerequisites ----
log "Installing system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget jq netcat-openbsd >/dev/null 2>&1 || apt-get install -y curl wget jq netcat >/dev/null 2>&1
log "Packages installed"

# ---- Disable swap ----
log "Disabling swap..."
swapoff -a || true
sed -i '/swap/d' /etc/fstab || true

# ---- Kernel modules ----
log "Loading kernel modules..."
modprobe overlay || true
modprobe br_netfilter || true

mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/rke2.conf <<'EOF'
overlay
br_netfilter
EOF

# ---- Kernel parameters ----
log "Configuring kernel parameters..."
cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null 2>&1 || true

# ---- Wait for master port 9345 with timeout ----
log "Checking connectivity to master at $MASTER_IP:9345..."
WAITED=0
MAX_WAIT=300  # 5 minutes max

until nc -z -w 5 $MASTER_IP 9345 2>/dev/null; do
  WAITED=$((WAITED + 5))
  log "  [$WAITED s] Cannot reach master:9345 yet..."
  
  if [ $WAITED -ge $MAX_WAIT ]; then
    log "ERROR: Could not reach master at $MASTER_IP:9345 after $MAX_WAIT seconds"
    log "Checking network connectivity..."
    ping -c 3 $MASTER_IP || log "Cannot ping master"
    log "Possible causes:"
    log "  1. Security group blocking port 9345"
    log "  2. RKE2 server not running on master"
    log "  3. Wrong master IP"
    exit 1
  fi
  sleep 5
done
log "SUCCESS: Master $MASTER_IP:9345 is reachable"

# ---- Clean any previous RKE2 installation ----
log "Cleaning any previous RKE2 installation..."
if systemctl is-active rke2-agent >/dev/null 2>&1; then
  systemctl stop rke2-agent || true
fi
if [ -f /usr/local/bin/rke2-killall.sh ]; then
  /usr/local/bin/rke2-killall.sh 2>/dev/null || true
fi
rm -rf /etc/rancher/rke2 /var/lib/rancher/rke2 /run/rke2 /run/k3s /var/run/rke2
log "Cleanup complete"

# ---- Create RKE2 config ----
log "Creating RKE2 agent config..."
mkdir -p /etc/rancher/rke2

# Debug: Show token format (hide actual token)
TOKEN_PREFIX=$(echo "$RKE2_TOKEN" | cut -c1-20)
log "Token prefix: ${TOKEN_PREFIX}... (length: ${#RKE2_TOKEN})"

cat > /etc/rancher/rke2/config.yaml <<EOF
server: https://$MASTER_IP:9345
token: "$RKE2_TOKEN"
node-label:
  - "node-role=worker"
  - "environment=$ENVIRONMENT"
  - "project=$PROJECT_NAME"
EOF

log "RKE2 config created at /etc/rancher/rke2/config.yaml"

# ---- Install RKE2 agent ----
log "Installing RKE2 agent (channel: $RKE2_VERSION)..."
if [[ "$RKE2_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_VERSION="$RKE2_VERSION" sh -
else
  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_CHANNEL="$RKE2_VERSION" sh -
fi
log "RKE2 agent installed"

# ---- Enable and start RKE2 agent ----
log "Starting RKE2 agent service..."
systemctl daemon-reload
systemctl enable rke2-agent.service

# Start with timeout monitoring
log "Starting rke2-agent (will monitor for 10 minutes)..."
systemctl start rke2-agent.service

# ---- Wait for agent with detailed logging ----
WAITED=0
MAX_WAIT=600  # 10 minutes
CHECK_INTERVAL=10

while [ $WAITED -lt $MAX_WAIT ]; do
  sleep $CHECK_INTERVAL
  WAITED=$((WAITED + CHECK_INTERVAL))
  
  # Check if service is active
  if systemctl is-active --quiet rke2-agent.service; then
    log "SUCCESS: rke2-agent is active after ${WAITED}s"
    
    # Additional check: verify the node actually joined
    sleep 5
    if systemctl is-active --quiet rke2-agent.service; then
      log "Worker node setup completed successfully"
      exit 0
    fi
  fi
  
  # Show progress every 30 seconds
  if [ $((WAITED % 30)) -eq 0 ]; then
    log "[$WAITED s] Still waiting for rke2-agent..."
    
    # Check for errors in logs
    RECENT_ERRORS=$(journalctl -u rke2-agent --since "1 minute ago" -q 2>/dev/null | grep -i "error\|fail" | head -3 || true)
    if [ -n "$RECENT_ERRORS" ]; then
      log "Recent errors found:"
      echo "$RECENT_ERRORS" | while read line; do log "  $line"; done
    fi
  fi
  
  # Check if service failed
  if systemctl is-failed --quiet rke2-agent.service; then
    log "ERROR: rke2-agent service has failed"
    journalctl -u rke2-agent -n 50 --no-pager || true
    exit 1
  fi
done

log "ERROR: rke2-agent did not become active within $MAX_WAIT seconds"
journalctl -u rke2-agent -n 100 --no-pager || true
exit 1
