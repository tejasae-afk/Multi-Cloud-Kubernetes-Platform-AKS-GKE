output "traffic_manager_profile_id" {
  description = "Traffic Manager profile ID."
  value       = azurerm_traffic_manager_profile.this.id
}

output "traffic_manager_profile_name" {
  description = "Traffic Manager profile name."
  value       = azurerm_traffic_manager_profile.this.name
}

output "traffic_manager_profile_fqdn" {
  description = "Traffic Manager profile FQDN."
  value       = azurerm_traffic_manager_profile.this.fqdn
}

output "shared_hostname" {
  description = "Public hostname that should point at the Traffic Manager profile."
  value       = var.shared_hostname
}

output "cluster_endpoints" {
  description = "Cluster-specific public hostnames behind Traffic Manager."
  value = {
    gke = azurerm_traffic_manager_external_endpoint.gke.target
    aks = azurerm_traffic_manager_external_endpoint.aks.target
  }
}
