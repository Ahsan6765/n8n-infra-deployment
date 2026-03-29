
# =============================================================================
# K8s Master Module – EC2 Instance (RKE2 Server)
# =============================================================================

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_network_interface" "master" {
  subnet_id       = var.subnet_id
  security_groups = var.security_group_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-master-eni"
  }
}

resource "aws_eip" "master" {
  domain            = "vpc"
  network_interface = aws_network_interface.master.id

  tags = {
    Name                                        = "${var.project_name}-${var.environment}-master-eip"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  depends_on = [aws_network_interface.master]
}

resource "aws_instance" "master" {
  ami                  = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = var.iam_instance_profile

  network_interface {
    network_interface_id = aws_network_interface.master.id
    device_index         = 0
  }

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = var.volume_type
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name                                        = "${var.project_name}-${var.environment}-master-root"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name                                        = "${var.project_name}-${var.environment}-master"
    Role                                        = "master"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_eip.master]
}

# =============================================================================
# Wait for SSH & cloud-init
# =============================================================================
resource "null_resource" "master_provisioner_wait" {
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init...'",
      "cloud-init status --wait || true",
      "echo 'System ready'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_eip.master.public_ip
      timeout     = "10m"
    }
  }

  depends_on = [aws_instance.master]
}

# =============================================================================
# Copy and execute master.sh in ONE step (avoids multiple SSH connections)
# =============================================================================
resource "null_resource" "master_provisioner" {
  provisioner "file" {
    source      = "${var.scripts_dir}/master.sh"
    destination = "/tmp/master.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_eip.master.public_ip
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/master.sh",
      "sudo bash /tmp/master.sh --domain '${var.domain_name}' --environment '${var.environment}' --project '${var.project_name}' --rke2-version '${var.rke2_version}'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_eip.master.public_ip
      timeout     = "40m"
    }
  }

  depends_on = [null_resource.master_provisioner_wait]
}

# =============================================================================
# Retrieve kubeconfig (runs in parallel with token generation)
# =============================================================================
resource "null_resource" "master_provisioner_kubeconfig" {
  provisioner "local-exec" {
    command = <<-EOT
      PRIVATE_KEY='${var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem"}'
      MASTER_IP='${aws_eip.master.public_ip}'
      KUBECONFIG_FILE='${path.root}/kubeconfig-${var.environment}.yaml'
      MAX_RETRIES=30
      RETRY_DELAY=10

      echo "[INFO] Retrieving kubeconfig from $MASTER_IP..."
      for i in $(seq 1 $MAX_RETRIES); do
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
               -i "$PRIVATE_KEY" ubuntu@$MASTER_IP:/tmp/kubeconfig.yaml \
               "$KUBECONFIG_FILE" 2>/dev/null; then
          
          FILE_SIZE=$(wc -c < "$KUBECONFIG_FILE" 2>/dev/null || echo 0)
          if [ "$FILE_SIZE" -gt 100 ]; then
            sed -i "s/127.0.0.1/${aws_eip.master.public_ip}/g" "$KUBECONFIG_FILE"
            echo "[SUCCESS] Kubeconfig saved ($FILE_SIZE bytes)"
            exit 0
          fi
        fi
        echo "[INFO] Attempt $i/$MAX_RETRIES: kubeconfig not ready, waiting..."
        sleep $RETRY_DELAY
      done

      echo "[ERROR] Failed to retrieve kubeconfig"
      exit 1
    EOT
  }

  depends_on = [null_resource.master_provisioner]
}

# =============================================================================
# Generate and retrieve RKE2 Token (using local-exec only, no remote-exec)
# =============================================================================
resource "null_resource" "master_provisioner_token" {
  provisioner "local-exec" {
    command = <<-EOT
      PRIVATE_KEY='${var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem"}'
      MASTER_IP='${aws_eip.master.public_ip}'
      TOKEN_FILE='${path.root}/rke2-token-${var.environment}.txt'
      MAX_RETRIES=60
      RETRY_DELAY=5

      echo "[INFO] Generating fresh RKE2 token from master..."
      
      # First wait for rke2-server to be active
      for i in $(seq 1 60); do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$PRIVATE_KEY" ubuntu@$MASTER_IP "sudo systemctl is-active rke2-server" >/dev/null 2>&1; then
          echo "[INFO] RKE2 server is active"
          break
        fi
        echo "[INFO] Waiting for rke2-server to be active... ($i/60)"
        sleep 5
      done

      # Now generate fresh token
      for i in $(seq 1 $MAX_RETRIES); do
        TOKEN_CONTENT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
          -i "$PRIVATE_KEY" ubuntu@$MASTER_IP \
          "sudo /usr/local/bin/rke2 token create --ttl 8760h 2>/dev/null || echo ''")
        
        if [ -n "$TOKEN_CONTENT" ] && echo "$TOKEN_CONTENT" | grep -q "^K10"; then
          echo "$TOKEN_CONTENT" > "$TOKEN_FILE"
          echo "[SUCCESS] Fresh token saved (length: $(echo -n "$TOKEN_CONTENT" | wc -c))"
          exit 0
        fi
        
        echo "[INFO] Attempt $i/$MAX_RETRIES: Token not ready, retrying..."
        sleep $RETRY_DELAY
      done

      echo "[ERROR] Failed to generate token"
      exit 1
    EOT
  }

  depends_on = [null_resource.master_provisioner]
}
