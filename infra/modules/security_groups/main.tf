# =============================================================================
# Security Groups Module – Master SG and Worker SG
# =============================================================================

# ---- Master Security Group ----
resource "aws_security_group" "master" {
  name        = "${var.project_name}-${var.environment}-master-sg"
  description = "Security group for the Kubernetes master node (RKE2 server)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-master-sg"
  }
}

# Master standard rules
resource "aws_security_group_rule" "master_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_ssh_cidr]
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_etcd" {
  type              = "ingress"
  from_port         = 2379
  to_port           = 2380
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_kubelet" {
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_controller" {
  type              = "ingress"
  from_port         = 10257
  to_port           = 10257
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_scheduler" {
  type              = "ingress"
  from_port         = 10259
  to_port           = 10259
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.master.id
}

# ---- Worker Security Group ----
resource "aws_security_group" "worker" {
  name        = "${var.project_name}-${var.environment}-worker-sg"
  description = "Security group for Kubernetes worker nodes (RKE2 agents)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-worker-sg"
  }
}

# Worker standard rules
resource "aws_security_group_rule" "worker_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_ssh_cidr]
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_nodeport" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker.id
}

# ---- Cross-Group Rules (Breaking the Cycle) ----

# Workers -> Master (RKE2 Supervisor & VXLAN)
resource "aws_security_group_rule" "workers_to_master_supervisor" {
  type                     = "ingress"
  from_port                = 9345
  to_port                  = 9345
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

resource "aws_security_group_rule" "workers_to_master_vxlan" {
  type                     = "ingress"
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

resource "aws_security_group_rule" "workers_to_master_all" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

# Master -> Workers (Kubelet & VXLAN)
resource "aws_security_group_rule" "master_to_workers_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.worker.id
}

resource "aws_security_group_rule" "master_to_workers_vxlan" {
  type                     = "ingress"
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.worker.id
}
