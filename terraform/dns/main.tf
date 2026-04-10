locals {
  zone_fqdn            = endswith(var.public_dns_zone_name, ".") ? var.public_dns_zone_name : "${var.public_dns_zone_name}."
  gke_edge_fqdn        = trimsuffix("${var.gke_edge_record_name}.${local.zone_fqdn}", ".")
  platform_record_fqdn = "${var.public_app_record_name}.${local.zone_fqdn}"
  traffic_manager_fqdn = trimsuffix(azurerm_traffic_manager_profile.global.fqdn, ".")
}

resource "azurerm_resource_group" "dns" {
  name     = var.azure_resource_group_name
  location = var.azure_location
  tags     = var.tags
}

resource "google_dns_managed_zone" "public" {
  project     = var.gcp_project_id
  name        = var.gcp_zone_name
  dns_name    = local.zone_fqdn
  description = "Public DNS zone for the multi-cloud platform edge."
  labels      = var.labels
}

# TODO: configure the GKE edge record once the ingress gateway service owns the reserved IP.
resource "google_dns_record_set" "gke_edge" {
  project      = var.gcp_project_id
  managed_zone = google_dns_managed_zone.public.name
  name         = "${var.gke_edge_record_name}.${local.zone_fqdn}"
  type         = "A"
  ttl          = 60
  rrdatas      = [var.gke_edge_ip_address]
}

resource "azurerm_traffic_manager_profile" "global" {
  name                   = var.traffic_manager_profile_name
  resource_group_name    = azurerm_resource_group.dns.name
  traffic_routing_method = "Weighted"
  profile_status         = "Enabled"
  tags                   = var.tags

  dns_config {
    relative_name = var.traffic_manager_relative_name
    ttl           = 30
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/"
    expected_status_code_ranges  = ["200-399"]
    interval_in_seconds          = 30
    timeout_in_seconds           = 9
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_external_endpoint" "gke" {
  name       = "gke-edge"
  profile_id = azurerm_traffic_manager_profile.global.id
  target     = local.gke_edge_fqdn
  weight     = var.gke_endpoint_weight
  enabled    = true
}

resource "azurerm_traffic_manager_azure_endpoint" "aks" {
  name               = "aks-edge"
  profile_id         = azurerm_traffic_manager_profile.global.id
  target_resource_id = var.aks_public_ip_id
  weight             = var.aks_endpoint_weight
  enabled            = true
}

resource "google_dns_record_set" "platform" {
  project      = var.gcp_project_id
  managed_zone = google_dns_managed_zone.public.name
  name         = local.platform_record_fqdn
  type         = "CNAME"
  ttl          = 60
  rrdatas      = ["${local.traffic_manager_fqdn}."]
}
