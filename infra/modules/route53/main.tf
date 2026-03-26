# =============================================================================
# Route 53 Module – Hosted Zone and DNS Records
# =============================================================================

# ---- Create or reference existing Hosted Zone ----
resource "aws_route53_zone" "main" {
  count = var.create_zone ? 1 : 0
  name  = var.domain_name

  tags = {
    Name        = var.domain_name
    Project     = var.project_name
    Environment = var.environment
  }
}

locals {
  zone_id = var.create_zone ? aws_route53_zone.main[0].zone_id : null
}

# ---- A Record – Kubernetes API Server ----
# Only created if a hosted zone is being managed
resource "aws_route53_record" "api" {
  count   = var.create_zone ? 1 : 0
  zone_id = local.zone_id
  name    = "k8s.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.master_public_ip]
}

# ---- Wildcard A Record – Cluster Services / Ingress ----
# Only created if a hosted zone is being managed
resource "aws_route53_record" "wildcard" {
  count   = var.create_zone ? 1 : 0
  zone_id = local.zone_id
  name    = "*.k8s.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.master_public_ip]
}

# ---- A Record – Raw domain apex (optional) ----
# Only created if a hosted zone is being managed
resource "aws_route53_record" "apex" {
  count   = var.create_zone ? 1 : 0
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [var.master_public_ip]
}
