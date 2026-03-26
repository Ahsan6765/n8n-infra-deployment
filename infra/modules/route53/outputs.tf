output "zone_id" {
  description = "ID of the Route 53 hosted zone."
  value       = local.zone_id
}

output "zone_name" {
  description = "Name of the Route 53 hosted zone."
  value       = var.domain_name
}

output "name_servers" {
  description = "Name servers for the hosted zone (update your domain registrar with these)."
  value       = var.create_zone ? aws_route53_zone.main[0].name_servers : []
}

output "api_dns_name" {
  description = "FQDN for the Kubernetes API server."
  value       = var.create_zone ? aws_route53_record.api[0].fqdn : null
}

output "wildcard_dns_name" {
  description = "Wildcard DNS FQDN for cluster services."
  value       = var.create_zone ? aws_route53_record.wildcard[0].fqdn : null
}

output "apex_dns_name" {
  description = "FQDN for the domain apex."
  value       = var.create_zone ? aws_route53_record.apex[0].fqdn : null
}
