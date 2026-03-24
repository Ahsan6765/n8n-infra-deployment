# =============================================================================
# K8s Master Module – EC2 Instance (RKE2 Server)
# =============================================================================

# ---- Latest Ubuntu 22.04 LTS AMI ----
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# ---- Render user-data from template ----
data "template_file" "userdata" {
  template = file("${path.module}/userdata.sh.tpl")

  vars = {
    project_name = var.project_name
    environment  = var.environment
    domain_name  = var.domain_name
    rke2_version = var.rke2_version
  }
}

# ---- Master EC2 Instance ----
resource "aws_instance" "master" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  key_name                    = var.key_name
  iam_instance_profile        = var.iam_instance_profile
  user_data                   = data.template_file.userdata.rendered
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = var.volume_type
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-${var.environment}-master-root"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional" # IMDSv1 needed for userdata curl calls
    http_put_response_hop_limit = 2
  }

  tags = {
    Name                                        = "${var.project_name}-${var.environment}-master"
    Role                                        = "master"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [
      ami,       # avoid replacement on AMI update
      user_data, # avoid replacement if userdata tweaked post-bootstrap
    ]
  }
}

# ---- Elastic IP for master ----
resource "aws_eip" "master" {
  instance = aws_instance.master.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-master-eip"
  }
}

# ---- SSM Parameter – RKE2 token (written by user-data, read by workers) ----
# This data source is only used to expose the token as a module output.
# The actual value is written by the master's user-data script.
data "aws_ssm_parameter" "rke2_token" {
  name            = "/${var.project_name}/${var.environment}/rke2/token"
  with_decryption = true

  # Only available after master has bootstrapped; depends_on prevents 
  # plan-time lookup failures.
  depends_on = [aws_instance.master]
}
