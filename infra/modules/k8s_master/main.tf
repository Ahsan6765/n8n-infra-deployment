

# =============================================================================
# K8s Master Module – EC2 Instance (RKE2 Server)
# =============================================================================

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# -----------------------------------------------------------------------------
# Network Interface with fixed private IP
# -----------------------------------------------------------------------------
resource "aws_network_interface" "master" {
  subnet_id       = var.subnet_id
  security_groups = var.security_group_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-master-eni"
  }
}

# -----------------------------------------------------------------------------
# Elastic IP for public access
# -----------------------------------------------------------------------------
resource "aws_eip" "master" {
  domain            = "vpc"
  network_interface = aws_network_interface.master.id

  tags = {
    Name                                        = "${var.project_name}-${var.environment}-master-eip"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  depends_on = [aws_network_interface.master]
}

# -----------------------------------------------------------------------------
# Master EC2 Instance
# -----------------------------------------------------------------------------
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
    http_tokens                 = "required"
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
# Provisioning: Copy and execute master setup script
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Wait for cloud-init to complete
# -----------------------------------------------------------------------------
resource "null_resource" "wait_for_cloud_init" {
  triggers = {
    instance_id = aws_instance.master.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = aws_eip.master.public_ip
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'System ready'"
    ]
  }

  depends_on = [aws_instance.master]
}

# -----------------------------------------------------------------------------
# 2. Copy master setup script and token file to instance
# -----------------------------------------------------------------------------
resource "null_resource" "copy_master_script" {
  triggers = {
    instance_id = aws_instance.master.id
    script_hash = filemd5("${var.scripts_dir}/master.sh")
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = aws_eip.master.public_ip
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${var.scripts_dir}/master.sh"
    destination = "/tmp/master.sh"
  }

  # Write token to a temporary file on remote instance
  provisioner "file" {
    content     = var.rke2_token
    destination = "/tmp/.rke2-token"
  }

  depends_on = [null_resource.wait_for_cloud_init]
}

# -----------------------------------------------------------------------------
# 3. Execute master setup script with parameters
# -----------------------------------------------------------------------------
resource "null_resource" "run_master_setup" {
  triggers = {
    instance_id = aws_instance.master.id
    script_hash = filemd5("${var.scripts_dir}/master.sh")
    token_hash  = md5(var.rke2_token)
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = aws_eip.master.public_ip
    timeout     = "30m"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/master.sh",
      "sudo bash /tmp/master.sh --token '${var.rke2_token}' --domain '${var.domain_name}' --environment '${var.environment}' --project '${var.project_name}' --rke2-version '${var.rke2_version}'"
    ]
  }

  depends_on = [null_resource.copy_master_script]
}

# -----------------------------------------------------------------------------
# 4. Retrieve kubeconfig from master
# -----------------------------------------------------------------------------
resource "null_resource" "retrieve_kubeconfig" {
  triggers = {
    instance_id = aws_instance.master.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = aws_eip.master.public_ip
    timeout     = "5m"
  }

  provisioner "local-exec" {
    command = <<-EOT
      MAX_RETRIES=30
      RETRY_DELAY=10

      echo "Retrieving kubeconfig from master..."
      for i in $(seq 1 $MAX_RETRIES); do
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
               -i "${var.ssh_private_key_path}" \
               ubuntu@${aws_eip.master.public_ip}:/tmp/kubeconfig.yaml \
               "${path.root}/kubeconfig-${var.environment}.yaml" 2>/dev/null; then

          # Replace 127.0.0.1 with master public IP
          sed -i.bak "s/127.0.0.1/${aws_eip.master.public_ip}/g" "${path.root}/kubeconfig-${var.environment}.yaml"
          rm -f "${path.root}/kubeconfig-${var.environment}.yaml.bak"
          echo "✓ Kubeconfig retrieved successfully"
          exit 0
        fi
        echo "Attempt $i/$MAX_RETRIES: kubeconfig not ready, waiting..."
        sleep $RETRY_DELAY
      done

      echo "✗ Failed to retrieve kubeconfig after $MAX_RETRIES attempts"
      exit 1
    EOT
  }

  depends_on = [null_resource.run_master_setup]
}