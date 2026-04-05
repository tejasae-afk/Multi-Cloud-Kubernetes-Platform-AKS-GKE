terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.66.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  # I kept more public weight on GKE because the central monitoring stack lives there.
  profile_name   = "${var.name_prefix}-tm"
  relative_name  = var.profile_relative_name != "" ? var.profile_relative_name : "${var.name_prefix}-edge"
  tags = {
    project     = "multi-cloud-k8s"
    environment = var.environment
    managed-by  = "terraform"
  }
}

resource "azurerm_resource_group" "routing" {
  name     = var.resource_group_name
  location = var.resource_group_location
  tags     = local.tags
}

resource "azurerm_traffic_manager_profile" "this" {
  name                   = local.profile_name
  resource_group_name    = azurerm_resource_group.routing.name
  traffic_routing_method = "Weighted"
  profile_status         = "Enabled"

  dns_config {
    relative_name = local.relative_name
    ttl           = var.dns_ttl
  }

  # Fast probes plus a short TTL gave me a decent failover window without hammering the app.
  monitor_config {
    protocol                    = "HTTPS"
    port                        = 443
    path                        = var.health_probe_path
    interval_in_seconds         = var.probe_interval_seconds
    timeout_in_seconds          = var.probe_timeout_seconds
    tolerated_number_of_failures = var.tolerated_failures
    expected_status_code_ranges = [
      "200-299"
    ]
  }

  tags = local.tags
}

resource "azurerm_traffic_manager_external_endpoint" "gke" {
  profile_id = azurerm_traffic_manager_profile.this.id
  name       = "${var.name_prefix}-gke"
  target     = var.gke_endpoint_fqdn
  weight     = var.gke_weight
}

resource "azurerm_traffic_manager_external_endpoint" "aks" {
  profile_id = azurerm_traffic_manager_profile.this.id
  name       = "${var.name_prefix}-aks"
  target     = var.aks_endpoint_fqdn
  weight     = var.aks_weight
}

# TODO: move the public CNAME into the zone automation once I stop changing hostnames every other weekend.
