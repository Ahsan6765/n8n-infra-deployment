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

data "aws_route53_zone" "existing" {
  count        = var.create_zone ? 0 : 1
  name         = var.domain_name
  private_zone = false
}

locals {
  zone_id = var.create_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}

# ---- A Record – Kubernetes API Server ----
resource "aws_route53_record" "api" {
  zone_id = local.zone_id
  name    = "k8s.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.master_public_ip]
}

# ---- Wildcard A Record – Cluster Services / Ingress ----
resource "aws_route53_record" "wildcard" {
  zone_id = local.zone_id
  name    = "*.k8s.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.master_public_ip]
}

# ---- A Record – Raw domain apex (optional) ----
resource "aws_route53_record" "apex" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [var.master_public_ip]
}
