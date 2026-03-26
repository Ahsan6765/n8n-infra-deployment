# =============================================================================
# IAM Module – EC2 Node Role, Policy, Instance Profile
# =============================================================================

# ---- Trust Policy ----
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---- Node IAM Role ----
resource "aws_iam_role" "node" {
  name               = "${var.project_name}-${var.environment}-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for K8s cluster EC2 nodes"

  # NOTE: Tags not applied to IAM role due to organizational policy restrictions.
  # Tags are applied to other resources (instances, volumes, etc.) via resource defaults.
}

# ---- Inline Policy – Node Permissions ----
data "aws_iam_policy_document" "node_permissions" {
  # EC2 metadata & describe (required by cloud-provider and RKE2)
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:DescribeAvailabilityZones",
      "ec2:CreateSecurityGroup",
      "ec2:CreateRoute",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:AttachVolume",
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:DetachVolume",
    ]
    resources = ["*"]
  }

  # ELB for Kubernetes LoadBalancer services
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:RegisterTargets",
    ]
    resources = ["*"]
  }

  # Autoscaling describe (required by K8s cluster autoscaler)
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
    ]
    resources = ["*"]
  }

  # S3 – read cluster artifacts
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [var.artifact_bucket_arn, "${var.artifact_bucket_arn}/*"]
  }

  # SSM Session Manager (optional passwordless access)
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "node" {
  name   = "${var.project_name}-${var.environment}-node-policy"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.node_permissions.json
}

# ---- Instance Profile ----
resource "aws_iam_instance_profile" "node" {
  name = "${var.project_name}-${var.environment}-node-profile"
  role = aws_iam_role.node.name

  tags = {
    Name = "${var.project_name}-${var.environment}-node-profile"
  }
}
