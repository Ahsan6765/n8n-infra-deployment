# # =============================================================================
# # K8s Worker Module – EC2 Instances (RKE2 Agents)
# # =============================================================================

# ---- Latest Ubuntu 22.04 LTS AMI ----
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# ---- Worker EC2 Instances ----
# Note: RKE2 setup is handled via provisioners that execute worker.sh scripts
# Instances wait for master to be ready before attempting to join
resource "aws_instance" "worker" {
  count              = var.worker_count
  ami                = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type      = var.instance_type
  subnet_id          = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.security_group_ids
  key_name           = var.key_name
  iam_instance_profile = var.iam_instance_profile

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

# ---- Worker Provisioners (separate resources to avoid dependency issues) ----
resource "null_resource" "worker_provisioner" {
  count = var.worker_count

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'System ready for RKE2 worker setup'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_instance.worker[count.index].public_ip
      timeout     = "5m"
    }
  }

  provisioner "file" {
    source      = "${var.scripts_dir}/worker.sh"
    destination = "/tmp/worker.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_instance.worker[count.index].public_ip
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/worker.sh",
      "sudo /tmp/worker.sh --master-ip '${var.master_private_ip}' --token '${var.rke2_token}' --environment '${var.environment}' --project '${var.project_name}' --rke2-version '${var.rke2_version}'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${path.root}/cluster-key.pem")
      host        = aws_instance.worker[count.index].public_ip
      timeout     = "30m"
    }
  }

  depends_on = [aws_instance.worker]
}