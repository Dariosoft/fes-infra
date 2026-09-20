variable "enable_vps_provisioning" {
  description = "Explicit safety switch. Enabling it permits Hostinger purchases and resource changes."
  type        = bool
  default     = false
}

variable "plan" {
  description = "Hostinger API plan identifier, not the display name."
  type        = string
  default     = "REPLACE_WITH_HOSTINGER_PLAN_ID"
}

variable "data_center_id" {
  description = "Hostinger data center ID. Confirm Brazil availability through the API before enabling provisioning."
  type        = number
  default     = 0
}

variable "template_id" {
  description = "Hostinger Ubuntu LTS template ID."
  type        = number
  default     = 0
}

variable "hostname" {
  description = "VPS fully qualified hostname."
  type        = string
  default     = "k3s.REPLACE_BASE_DOMAIN"
}

variable "ssh_public_key" {
  description = "SSH Ed25519 public key installed on the VPS."
  type        = string
  default     = ""
  sensitive   = true
}

variable "root_password" {
  description = "Optional root password. Prefer SSH and allow Hostinger to generate it."
  type        = string
  default     = null
  sensitive   = true
  nullable    = true
}
