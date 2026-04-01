output "public_zone_name_servers" {
  description = "Cloud DNS authoritative name servers for the public zone."
  value       = google_dns_managed_zone.public.name_servers
}

output "traffic_manager_fqdn" {
  description = "Traffic Manager FQDN."
  value       = trimsuffix(azurerm_traffic_manager_profile.global.fqdn, ".")
}

output "platform_hostname" {
  description = "Platform hostname in Cloud DNS."
  value       = trimsuffix(google_dns_record_set.platform.name, ".")
}

output "gke_edge_hostname" {
  description = "Cloud DNS name that points at the reserved GKE ingress IP."
  value       = trimsuffix(google_dns_record_set.gke_edge.name, ".")
}
