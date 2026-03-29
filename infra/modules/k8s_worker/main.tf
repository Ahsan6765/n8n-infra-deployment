# =============================================================================
# K8s Worker Module – EC2 Instances (RKE2 Agents)
# =============================================================================

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = var.volume_type
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name                                        = "${var.project_name}-${var.environment}-worker-${count.index + 1}-root"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name                                        = "${var.project_name}-${var.environment}-worker-${count.index + 1}"
    Role                                        = "worker"
    WorkerIndex                                 = count.index + 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [
      ami,
    ]
  }
}

# =============================================================================
# Worker Setup - Using local-exec for better reliability
# =============================================================================
resource "null_resource" "worker_provisioner" {
  count = var.worker_count

  triggers = {
    worker_id  = aws_instance.worker[count.index].id
    token_hash = md5(var.rke2_token)
    master_ip  = var.master_private_ip
  }

  # Copy script via local SCP
  provisioner "local-exec" {
    command = <<-EOT
      echo "[worker-${count.index + 1}] Preparing to provision worker..."
      
      PRIVATE_KEY="${var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem"}"
      WORKER_IP="${aws_instance.worker[count.index].public_ip}"
      MASTER_IP="${var.master_private_ip}"
      TOKEN="${var.rke2_token}"
      
      echo "[worker-${count.index + 1}] Waiting for SSH to be available..."
      for i in $(seq 1 30); do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$PRIVATE_KEY" ubuntu@$WORKER_IP "echo 'SSH ready'" >/dev/null 2>&1; then
          echo "[worker-${count.index + 1}] SSH is available"
          break
        fi
        echo "[worker-${count.index + 1}] Waiting for SSH... ($i/30)"
        sleep 10
      done
      
      echo "[worker-${count.index + 1}] Copying worker.sh..."
      scp -o StrictHostKeyChecking=no -i "$PRIVATE_KEY" ${var.scripts_dir}/worker.sh ubuntu@$WORKER_IP:/tmp/worker.sh
      
      echo "[worker-${count.index + 1}] Executing worker.sh with timeout..."
      # Use timeout command to prevent hanging forever
      ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
          -i "$PRIVATE_KEY" ubuntu@$WORKER_IP \
          "sudo chmod +x /tmp/worker.sh && sudo timeout 600 /tmp/worker.sh --master-ip '$MASTER_IP' --token '$TOKEN' --environment '${var.environment}' --project '${var.project_name}' --rke2-version '${var.rke2_version}' 2>&1 | tee /home/ubuntu/worker-setup.log; exit $?" || {
        echo "[worker-${count.index + 1}] ERROR: Worker script failed or timed out"
        echo "[worker-${count.index + 1}] Checking logs remotely..."
        ssh -o StrictHostKeyChecking=no -i "$PRIVATE_KEY" ubuntu@$WORKER_IP "sudo tail -50 /var/log/rke2-worker-setup.log 2>/dev/null || echo 'No log file'" || true
        exit 1
      }
      
      echo "[worker-${count.index + 1}] Worker provisioning completed successfully"
    EOT
  }

  depends_on = [aws_instance.worker]
}
