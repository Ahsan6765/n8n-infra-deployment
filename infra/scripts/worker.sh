# #!/bin/bash
# # =============================================================================
# # RKE2 Worker Node Setup Script
# # =============================================================================
# # This script sets up a RKE2 agent (worker) on an Ubuntu 22.04 instance.
# # Run this script on each worker node after the master node is fully initialized.
# #
# # Usage: ./worker.sh --master-ip <PRIVATE_IP> --token <TOKEN> [OPTIONS]
# #
# # Required:
# #   --master-ip <IP>           Master node private IP address
# #   --token <TOKEN>            Cluster join token from master
# #
# # Optional:
# #   --environment <env>        Environment name (default: dev)
# #   --project <name>           Project name (default: n8n)
# #   --rke2-version <version>   RKE2 version channel (default: stable)
# #
# # Example:
# #   ./worker.sh --master-ip 10.0.1.10 --token "K123456789abc..." --environment prod
# # =============================================================================

# set -euo pipefail

# # ---- Logging Setup ----
# LOG_FILE="/var/log/rke2-worker-setup.log"
# mkdir -p "$(dirname "$LOG_FILE")"
# exec > >(tee -a "$LOG_FILE") 2>&1

# log_info() {
#   echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"
# }

# log_error() {
#   echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
# }

# log_warn() {
#   echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $1"
# }

# log_debug() {
#   echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $1"
# }

# # ---- Parse arguments ----
# MASTER_IP=""
# RKE2_TOKEN=""
# ENVIRONMENT="dev"
# PROJECT_NAME="n8n"
# RKE2_VERSION="stable"

# while [[ $# -gt 0 ]]; do
#   case $1 in
#     --master-ip)
#       MASTER_IP="$2"
#       shift 2
#       ;;
#     --token)
#       RKE2_TOKEN="$2"
#       shift 2
#       ;;
#     --environment)
#       ENVIRONMENT="$2"
#       shift 2
#       ;;
#     --project)
#       PROJECT_NAME="$2"
#       shift 2
#       ;;
#     --rke2-version)
#       RKE2_VERSION="$2"
#       shift 2
#       ;;
#     *)
#       log_error "Unknown option: $1"
#       exit 1
#       ;;
#   esac
# done

# # ---- Validate required arguments ----
# if [ -z "$MASTER_IP" ]; then
#   log_error "Missing required argument: --master-ip"
#   log_error "Usage: ./worker.sh --master-ip <IP> --token <TOKEN> [OPTIONS]"
#   exit 1
# fi

# if [ -z "$RKE2_TOKEN" ]; then
#   log_error "Missing required argument: --token"
#   log_error "Usage: ./worker.sh --master-ip <IP> --token <TOKEN>"
#   exit 1
# fi

# log_info "=========================================="
# log_info "RKE2 Worker Node Setup Starting"
# log_info "=========================================="
# log_info "Master IP: $MASTER_IP"
# log_info "Environment: $ENVIRONMENT"
# log_info "Project: $PROJECT_NAME"
# log_info "RKE2 Version: $RKE2_VERSION"
# log_info "Log File: $LOG_FILE"
# log_info "=========================================="

# # ---- Validate we're running with proper privileges ----
# if [[ $EUID -ne 0 ]]; then
#   log_error "This script requires elevated privileges (root/sudo)"
#   exit 1
# fi

# log_info "✓ Running with root privileges"

# # ---- System prerequisites ----
# log_info "Installing system packages with timeout protection..."
# export DEBIAN_FRONTEND=noninteractive

# # Update with timeout
# if ! timeout 120 apt-get update -y > /dev/null 2>&1; then
#   log_warn "apt-get update timed out or failed (continuing with cached packages)"
# fi

# # Install packages with timeout and flock to handle concurrent access
# if ! timeout 180 bash -c 'flock /var/lib/apt/lists/lock apt-get install -y curl wget git jq awscli' > /dev/null 2>&1; then
#   log_warn "apt-get install timed out (packages may already be installed or lock held)"
# fi

# log_info "✓ System packages ready"

# # ---- Disable swap (required by Kubernetes) ----
# log_info "Disabling swap..."
# timeout 30 swapoff -a || log_warn "Could not swapoff or it timed out (may not have swap)"
# sed -i '/swap/d' /etc/fstab || log_warn "Could not update fstab"
# log_info "✓ Swap disabled"

# # ---- Set kernel parameters for Kubernetes networking ----
# log_info "Configuring kernel parameters..."
# mkdir -p /etc/sysctl.d
# cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
# net.bridge.bridge-nf-call-iptables  = 1
# net.bridge.bridge-nf-call-ip6tables = 1
# net.ipv4.ip_forward                  = 1
# EOF
# sysctl --system > /dev/null 2>&1 || log_warn "sysctl configuration had issues"
# log_info "✓ Kernel parameters configured"

# # ---- Load overlay and br_netfilter kernel modules ----
# log_info "Loading kernel modules..."
# if ! modprobe overlay; then
#   log_warn "Could not load overlay module (may already be loaded)"
# fi
# if ! modprobe br_netfilter; then
#   log_warn "Could not load br_netfilter module (may already be loaded)"
# fi

# # Verify at least one module loaded
# if ! (lsmod | grep -q overlay) && ! (lsmod | grep -q br_netfilter); then
#   log_error "Neither overlay nor br_netfilter modules are loaded - RKE2 will fail"
#   exit 1
# fi

# mkdir -p /etc/modules-load.d
# cat >>/etc/modules-load.d/containerd.conf <<'EOF'
# overlay
# br_netfilter
# EOF
# log_info "✓ Kernel modules loaded"

# # ---- Retrieve instance metadata ----
# log_info "Retrieving instance metadata..."
# PRIVATE_IP=$(timeout 5 curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "UNKNOWN")
# INSTANCE_ID=$(timeout 5 curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "UNKNOWN")
# AVAILABILITY_ZONE=$(timeout 5 curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "UNKNOWN")
# log_info "✓ Instance metadata retrieved"
# log_info "  - Private IP: $PRIVATE_IP"
# log_info "  - Instance ID: $INSTANCE_ID"
# log_info "  - Availability Zone: $AVAILABILITY_ZONE"

# # ---- Wait for master node to be reachable (TCP port 9345) ----
# log_info "Checking master node API availability at $MASTER_IP:9345..."
# MAX_ATTEMPTS=36  # Reduced from 60 (10 min) to 36 (6 min with exponential backoff)
# ATTEMPT=0
# MASTER_READY=false
# BACKOFF_DELAY=5  # Start with 5 seconds

# while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
#   if timeout 3 bash -c "echo > /dev/tcp/$MASTER_IP/9345" 2>/dev/null; then
#     log_info "✓ Master node is reachable at $MASTER_IP:9345"
#     MASTER_READY=true
#     break
#   fi
#   ATTEMPT=$((ATTEMPT + 1))
  
#   # Calculate delay with short exponential backoff (cap at 10 seconds)
#   CURRENT_DELAY=$((BACKOFF_DELAY + (ATTEMPT - 1) / 4))  # Increase every 4 attempts
#   [ $CURRENT_DELAY -gt 10 ] && CURRENT_DELAY=10
  
#   if [ $ATTEMPT -le 5 ] || [ $((ATTEMPT % 6)) -eq 0 ]; then
#     ELAPSED=$((ATTEMPT * 5 + (ATTEMPT - 1) / 4 * 2))  # Rough estimate
#     log_info "  Attempt $ATTEMPT/$MAX_ATTEMPTS: Master not ready (waiting ${CURRENT_DELAY}s)"
#   fi
  
#   sleep "$CURRENT_DELAY"
# done

# if [ "$MASTER_READY" = false ]; then
#   log_error "Could not reach master at $MASTER_IP:9345 after ~6 minutes"
#   log_error ""
#   log_error "Possible causes:"
#   log_error "  1. Master node is not running or still initializing"
#   log_error "  2. Security group does not allow port 9345 from worker"
#   log_error "  3. Network connectivity issue between worker and master"
#   log_error "  4. Master IP address is incorrect (got: $MASTER_IP)"
#   log_error "  5. RKE2 master service failed to start"
#   log_error ""
#   log_error "Debugging steps:"
#   log_error "  - Verify master instance is running"
#   log_error "  - Check master security group inbound rules for port 9345"
#   log_error "  - From master, run: systemctl status rke2-server"
#   log_error "  - From master, check: journalctl -u rke2-server | head -50"
#   exit 1
# fi

# # ---- Validate token format ----
# log_info "Validating cluster token..."
# TOKEN_LEN=${#RKE2_TOKEN}

# if [ "$TOKEN_LEN" -lt 10 ]; then
#   log_error "Token appears invalid (too short: $TOKEN_LEN characters)"
#   log_error "Expected minimum length: 40 characters"
#   exit 1
# fi

# if [ "$TOKEN_LEN" -lt 40 ]; then
#   log_warn "Token is shorter than expected ($TOKEN_LEN chars), but continuing..."
# fi

# TOKEN_PREFIX=$(echo "$RKE2_TOKEN" | cut -c1-15)
# log_info "✓ Token validated (length: $TOKEN_LEN characters, prefix: ${TOKEN_PREFIX}...)"

# # ---- Create RKE2 config directory ----
# log_info "Creating RKE2 config directory..."
# mkdir -p /etc/rancher/rke2 || {
#   log_error "Failed to create /etc/rancher/rke2 directory"
#   exit 1
# }
# log_info "✓ RKE2 config directory created"

# # ---- Write RKE2 agent config ----
# log_info "Creating RKE2 agent configuration file..."
# cat > /etc/rancher/rke2/config.yaml <<EOF
# # RKE2 Agent Configuration
# # Generated: $(date)
# server: https://$MASTER_IP:9345
# token: "$RKE2_TOKEN"
# node-label:
#   - "node-role=worker"
#   - "environment=$ENVIRONMENT"
#   - "project=$PROJECT_NAME"
# EOF

# if [ ! -f /etc/rancher/rke2/config.yaml ]; then
#   log_error "Failed to create RKE2 config file at /etc/rancher/rke2/config.yaml"
#   exit 1
# fi

# log_info "✓ RKE2 agent configuration file created"
# log_debug "Config file location: /etc/rancher/rke2/config.yaml"

# # ---- Download and install RKE2 agent ----
# log_info "Downloading RKE2 agent installer (channel: $RKE2_VERSION) with 5-minute timeout..."
# if ! timeout 300 curl -sfL https://get.rke2.io | timeout 300 sh -s - agent 2>&1 | tee -a "$LOG_FILE"; then
#   log_error "Failed to download or install RKE2 agent (timeout or network issue)"
#   log_error "Possible causes:"
#   log_error "  - Network connectivity issue (cannot reach get.rke2.io)"
#   log_error "  - Invalid RKE2 version channel: $RKE2_VERSION"
#   log_error "  - Insufficient disk space"
#   exit 1
# fi
# log_info "✓ RKE2 agent installed successfully"

# # ---- Enable and start RKE2 agent ----
# log_info "Enabling and starting RKE2 agent service..."
# systemctl daemon-reload || {
#   log_error "Failed to reload systemctl daemon configuration"
#   exit 1
# }

# systemctl enable rke2-agent.service || {
#   log_error "Failed to enable rke2-agent service"
#   exit 1
# }

# log_debug "Starting rke2-agent service..."
# if ! systemctl start rke2-agent.service; then
#   log_error "Failed to start rke2-agent service"
#   log_error "Service status:"
#   systemctl status rke2-agent.service 2>&1 | tee -a "$LOG_FILE" || true
#   exit 1
# fi

# log_info "✓ RKE2 agent service started"

# # ---- Wait for agent to become active ----
# log_info "Waiting for RKE2 agent to initialize (up to 3 minutes)..."
# AGENT_READY=false
# AGENT_ATTEMPTS=0
# MAX_AGENT_ATTEMPTS=36  # 36 × 5 seconds = 3 minutes (reduced from 5 minutes)

# while [ $AGENT_ATTEMPTS -lt $MAX_AGENT_ATTEMPTS ]; do
#   AGENT_ATTEMPTS=$((AGENT_ATTEMPTS + 1))
  
#   if systemctl is-active rke2-agent &>/dev/null; then
#     log_info "✓ RKE2 agent service is active"
#     AGENT_READY=true
#     break
#   fi
  
#   # Show progress every 6 attempts (30 seconds)
#   if [ $((AGENT_ATTEMPTS % 6)) -eq 0 ]; then
#     ELAPSED=$((AGENT_ATTEMPTS * 5))
#     log_info "  [$ELAPSED seconds] Agent still initializing, waiting..."
#   fi
  
#   # Check for catastrophic failures
#   if systemctl status rke2-agent 2>&1 | grep -q "failed\|error\|inactive"; then
#     if [ $AGENT_ATTEMPTS -gt 3 ]; then
#       log_error "RKE2 agent service failed to start"
#       log_error "Service status:"
#       systemctl status rke2-agent 2>&1 | tee -a "$LOG_FILE" || true
#       exit 1
#     fi
#   fi
  
#   sleep 5
# done

# if [ "$AGENT_READY" = false ]; then
#   log_error "RKE2 agent failed to start within 3 minutes"
#   log_error "Recent service logs:"
#   journalctl -u rke2-agent -n 50 2>&1 | tee -a "$LOG_FILE" || true
#   exit 1
# fi

# # ---- Wait a bit longer for agent to register with cluster ----
# log_info "Waiting for agent to register with cluster (10 seconds)..."
# sleep 10

# # ---- Verify agent is still running ----
# log_info "Verifying RKE2 agent is running..."
# if ! systemctl is-active rke2-agent &>/dev/null; then
#   log_error "RKE2 agent is no longer running after initialization"
#   log_error "Recent service logs:"
#   journalctl -u rke2-agent -n 50 2>&1 | tee -a "$LOG_FILE" || true
#   exit 1
# fi

# log_info "✓ RKE2 agent is running and ready"

# # ---- Add RKE2 binaries to PATH for ubuntu user ----
# log_info "Configuring PATH for RKE2 binaries..."
# BASHRC_PATH="/home/ubuntu/.bashrc"
# if [ -f "$BASHRC_PATH" ]; then
#   if ! grep -q "/var/lib/rancher/rke2/bin" "$BASHRC_PATH" 2>/dev/null; then
#     cat <<'EOF' >> "$BASHRC_PATH"

# # RKE2 binaries PATH
# export PATH=$PATH:/var/lib/rancher/rke2/bin
# EOF
#     log_info "✓ Updated PATH in /home/ubuntu/.bashrc"
#   else
#     log_info "✓ PATH already configured in /home/ubuntu/.bashrc"
#   fi
# else
#   log_warn "Could not find /home/ubuntu/.bashrc (non-critical)"
# fi

# # ---- Final validation and logging ----
# log_info "=========================================="
# log_info "✓ RKE2 Worker Node Setup Complete"
# log_info "=========================================="
# log_info ""
# log_info "Worker node information:"
# log_info "  - Private IP: $PRIVATE_IP"
# log_info "  - Master IP: $MASTER_IP"
# log_info "  - Environment: $ENVIRONMENT"
# log_info "  - Project: $PROJECT_NAME"
# log_info "  - Status: Joining cluster..."
# log_info ""
# log_info "Next steps:"
# log_info "  1. Wait 1-2 minutes for the node to fully join the cluster"
# log_info "  2. From the master node, run:"
# log_info "       export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
# log_info "       kubectl get nodes"
# log_info "  3. This worker should appear in the output shortly"
# log_info ""
# log_info "Troubleshooting:"
# log_info "  If the node doesn't appear after 5 minutes:"
# log_info "    - Check this log file: $LOG_FILE"
# log_info "    - Check RKE2 agent status: systemctl status rke2-agent"
# log_info "    - View agent logs: journalctl -u rke2-agent -f"
# log_info "    - Verify network connectivity to master:"
# log_info "        ping $MASTER_IP"
# log_info "        telnet $MASTER_IP 9345"
# log_info "    - From master, check cluster status:"
# log_info "        export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
# log_info "        kubectl describe node $(hostname)"
# log_info "=========================================="
# log_info ""
# log_info "Setup completed successfully at $(date)"

# ============================================================================
# ============================================================================



#!/bin/bash
# =============================================================================
# RKE2 Worker Node Setup Script (Optimized for Terraform Provisioning)
# =============================================================================

#!/bin/bash
set -e
set -o pipefail

LOG_FILE="/var/log/rke2-worker-setup.log"
exec > >(tee -a $LOG_FILE) 2>&1

MASTER_IP=$1
NODE_TOKEN=$2

echo "Starting RKE2 worker setup..."
echo "Master IP: $MASTER_IP"

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Install dependencies
sudo apt-get update -y
sudo apt-get install -y curl

# Install RKE2
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -

# Create config
sudo mkdir -p /etc/rancher/rke2

cat <<EOF | sudo tee /etc/rancher/rke2/config.yaml
server: https://$MASTER_IP:9345
token: $NODE_TOKEN
EOF

# Enable and start agent
sudo systemctl enable rke2-agent
sudo systemctl start rke2-agent

echo "RKE2 worker setup completed"