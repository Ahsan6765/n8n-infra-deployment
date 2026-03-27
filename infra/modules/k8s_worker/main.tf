# # =============================================================================
# # K8s Worker Module – EC2 Instances (RKE2 Agents)
# # =============================================================================

# ---- Latest Ubuntu 22.04 LTS AMI ----
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# ---- Render user-data for each worker ----
data "template_file" "userdata" {
  template = file("${path.module}/userdata.sh.tpl")

  vars = {
    project_name      = var.project_name
    environment       = var.environment
    master_private_ip = var.master_private_ip
    rke2_token        = var.rke2_token
    rke2_version      = var.rke2_version
  }
}




#========================================================================================================================
#========testing =========

#========================================================================================================================

# ---- Worker EC2 Instances ----
resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
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
      user_data,
    ]
  }
}



#========================================================================================================================
#========================================================================================================================
#========================================================================================================================


# =============================================================================
# K8s Worker Module – EC2 Instances (RKE2 Agents)
# =============================================================================

# ---- Latest Ubuntu 22.04 LTS AMI ----
# data "aws_ssm_parameter" "ubuntu_ami" {
#   name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
# }

# # ---- Worker EC2 Instances ----
# resource "aws_instance" "worker" {
#   count                  = var.worker_count
#   ami                    = data.aws_ssm_parameter.ubuntu_ami.value
#   instance_type          = var.instance_type
#   subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
#   vpc_security_group_ids = var.security_group_ids
#   key_name               = var.key_name
#   iam_instance_profile   = var.iam_instance_profile

#   # ---- Replaced deprecated data "template_file" with built-in templatefile() ----
#   user_data = templatefile("${path.module}/userdata.sh.tpl", {
#     project_name      = var.project_name
#     environment       = var.environment
#     master_private_ip = var.master_private_ip
#     rke2_token        = var.rke2_token
#     rke2_version      = var.rke2_version
#   })

#   user_data_replace_on_change = true

#   root_block_device {
#     volume_size           = var.volume_size
#     volume_type           = var.volume_type
#     encrypted             = true
#     delete_on_termination = true

#     tags = {
#       Name                                        = "${var.project_name}-${var.environment}-worker-${count.index + 1}-root"
#       "kubernetes.io/cluster/${var.cluster_name}" = "owned"
#     }
#   }

#   metadata_options {
#     http_endpoint               = "enabled"
#     http_tokens                 = "required"
#     http_put_response_hop_limit = 2
#   }

#   tags = {
#     Name                                        = "${var.project_name}-${var.environment}-worker-${count.index + 1}"
#     Role                                        = "worker"
#     WorkerIndex                                 = tostring(count.index + 1)
#     "kubernetes.io/cluster/${var.cluster_name}" = "owned"
#   }

#   lifecycle {
#     ignore_changes = [
#       ami,
#       user_data,
#     ]
#   }
# }