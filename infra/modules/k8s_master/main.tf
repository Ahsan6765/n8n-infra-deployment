# =============================================================================
# K8s Master Module – EC2 Instance (RKE2 Server)
# =============================================================================

# ---- Latest Ubuntu 22.04 LTS AMI ----
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# ---- Get the primary network interface first ----
resource "aws_network_interface" "master" {
  subnet_id       = var.subnet_id
  security_groups = var.security_group_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-master-eni"
  }
}

# ---- Elastic IP for master ----
resource "aws_eip" "master" {
  domain            = "vpc"
  network_interface = aws_network_interface.master.id

  tags = {
    Name                                        = "${var.project_name}-${var.environment}-master-eip"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  depends_on = [aws_network_interface.master]
}

# ---- Master EC2 Instance ----
resource "aws_instance" "master" {
  ami               = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type     = var.instance_type
  key_name          = var.key_name
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
    ignore_changes = [
      ami,
    ]
  }

  depends_on = [aws_eip.master]
}

# ---- Provisioner: Wait for SSH to be available ----
resource "null_resource" "master_provisioner_wait" {
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'System ready for RKE2 setup'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_eip.master.public_ip
      timeout     = "5m"
    }
  }

  depends_on = [aws_instance.master, aws_eip.master]
}

# ---- Provisioner: Copy master setup script ----
resource "null_resource" "master_provisioner_copy" {
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

  depends_on = [null_resource.master_provisioner_wait]
}

# ---- Provisioner: Execute master setup script ----
resource "null_resource" "master_provisioner_execute" {
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/master.sh",
      "sudo /tmp/master.sh --domain '${var.domain_name}' --environment '${var.environment}' --project '${var.project_name}' --rke2-version '${var.rke2_version}'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_eip.master.public_ip
      timeout     = "30m"
    }
  }

  depends_on = [null_resource.master_provisioner_copy]
}

# ---- Provisioner: Retrieve and save cluster token locally ----
resource "null_resource" "master_provisioner_token" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Retrieving RKE2 token from master node (${aws_eip.master.public_ip})..."
      PRIVATE_KEY='${var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem"}'
      MASTER_IP='${aws_eip.master.public_ip}'
      TOKEN_FILE='${path.root}/rke2-token-${var.environment}.txt'
      MAX_ATTEMPTS=30
      ATTEMPT=0
      
      # Wait for the token file to be readable and non-empty on the master
      echo "Waiting for token file to be created on master..."
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        TOKEN_CONTENT=$(ssh -o ConnectTimeout=5 -o ConnectionAttempts=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$PRIVATE_KEY" ubuntu@$MASTER_IP "cat /tmp/rke2-token.txt 2>/dev/null" 2>/dev/null || echo "")
        if [ -n "$TOKEN_CONTENT" ] && [ $(echo -n "$TOKEN_CONTENT" | wc -c) -gt 40 ]; then
          echo "Token file found and valid on master, proceeding with retrieval..."
          break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
          echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Token not ready (size: $(echo -n \"$TOKEN_CONTENT\" | wc -c)), retrying in 5s..."
          sleep 5
        else
          echo "ERROR: Token file never appeared on master after $MAX_ATTEMPTS attempts"
          echo "Debugging: Checking RKE2 service status on master..."
          ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$PRIVATE_KEY" ubuntu@$MASTER_IP "systemctl status rke2-server --no-pager || echo 'RKE2 service failed'; cat /var/log/rke2-master-setup.log 2>/dev/null | tail -30 || echo 'No setup log found'" 2>&1 || true
          exit 1
        fi
      done
      
      # Now SCP the token file to local
      echo "Copying token to local system..."
      if scp -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$PRIVATE_KEY" ubuntu@$MASTER_IP:/tmp/rke2-token.txt "$TOKEN_FILE" 2>&1; then
        TOKEN_SIZE=$(wc -c < "$TOKEN_FILE")
        echo "[SUCCESS] Token retrieved and saved locally (size: $TOKEN_SIZE bytes)"
        exit 0
      else
        echo "[FAILED] SCP failed to retrieve token file"
        exit 1
      fi
    EOT
  }

  depends_on = [null_resource.master_provisioner_execute]
}

# ---- Provisioner: Retrieve kubeconfig from master ----
resource "null_resource" "master_provisioner_kubeconfig" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Retrieving kubeconfig from master node (${aws_eip.master.public_ip})..."
      PRIVATE_KEY='${var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem"}'
      MASTER_IP='${aws_eip.master.public_ip}'
      KUBECONFIG_FILE='${path.root}/kubeconfig-${var.environment}.yaml'
      MAX_ATTEMPTS=20
      ATTEMPT=0
      
      # First, wait for the kubeconfig file to exist on the master
      echo "Waiting for kubeconfig to be ready on master..."
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$PRIVATE_KEY" ubuntu@$MASTER_IP "test -f ~/.kube/config && wc -c < ~/.kube/config" 2>/dev/null | grep -q -v 0; then
          echo "Kubeconfig found on master, proceeding with retrieval..."
          break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
          echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Kubeconfig not ready yet, retrying in 5s..."
          sleep 5
        else
          echo "ERROR: Kubeconfig never appeared on master after $MAX_ATTEMPTS attempts"
          exit 1
        fi
      done
      
      # Now retrieve the kubeconfig
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if scp -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$PRIVATE_KEY" ubuntu@$MASTER_IP:~/.kube/config "$KUBECONFIG_FILE" 2>&1; then
          KUBECONFIG_SIZE=$(wc -c < "$KUBECONFIG_FILE")
          if [ "$KUBECONFIG_SIZE" -gt 100 ]; then
            echo "[SUCCESS] Kubeconfig retrieved (size: $KUBECONFIG_SIZE bytes)"
            exit 0
          else
            echo "Kubeconfig file exists but appears invalid (size: $KUBECONFIG_SIZE bytes), retrying..."
          fi
        fi
        ATTEMPT=$((ATTEMPT + 1))
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
          echo "SCP attempt $ATTEMPT/$MAX_ATTEMPTS failed, retrying in 5s..."
          sleep 5
        fi
      done
      
      echo "[FAILED] Could not retrieve valid kubeconfig after $MAX_ATTEMPTS SCP attempts"
      exit 1
    EOT
  }

  depends_on = [null_resource.master_provisioner_execute]
}
