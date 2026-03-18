variable "domain_name" {
  description = "Route 53 hosted zone domain name."
  type        = string
}

variable "create_zone" {
  description = "If true, create a new hosted zone; if false, use an existing zone."
  type        = bool
  default     = true
}

variable "master_public_ip" {
  description = "Public IP of the Kubernetes master node to use in DNS records."
  type        = string
}

variable "project_name" {
  description = "Project name prefix."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}
