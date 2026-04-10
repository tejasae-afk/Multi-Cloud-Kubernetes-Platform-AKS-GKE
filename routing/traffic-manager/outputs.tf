output "traffic_manager_profile_id" {
  description = "Traffic Manager profile resource ID."
  value       = azurerm_traffic_manager_profile.edge.id
}

output "traffic_manager_fqdn" {
  description = "Public trafficmanager.net hostname."
  value       = azurerm_traffic_manager_profile.edge.fqdn
}

output "public_hostname" {
  description = "Final public hostname if I let this module create the CNAME."
  value       = var.create_public_cname ? "${var.public_record_name}.${var.public_zone_name}" : null
}

output "azure_subscription_display_name" {
  description = "Subscription display name, mostly handy when I forget which account the runner used."
  value       = data.azurerm_subscription.current.display_name
}
