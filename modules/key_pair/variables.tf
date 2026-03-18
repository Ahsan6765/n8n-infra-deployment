variable "key_name" {
  description = "Name for the EC2 Key Pair."
  type        = string
}

variable "public_key" {
  description = "SSH public key material (OpenSSH format)."
  type        = string
  sensitive   = true
}
