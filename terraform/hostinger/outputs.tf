output "provisioning_enabled" {
  description = "Whether Terraform is allowed to create billable Hostinger resources."
  value       = var.enable_vps_provisioning
}

output "vps_ipv4" {
  description = "Public IPv4 address when a VPS has been provisioned or imported."
  value       = try(hostinger_vps.friendly_e_shop[0].ipv4_address, null)
}

output "vps_id" {
  description = "Hostinger VPS ID for import and operations."
  value       = try(hostinger_vps.friendly_e_shop[0].id, null)
}
