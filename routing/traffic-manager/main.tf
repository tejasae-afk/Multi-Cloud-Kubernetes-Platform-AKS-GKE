terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.66.0, < 5.0.0"
    }
  }

  backend "gcs" {}
}

provider "azurerm" {
  features {}

  subscription_id = var.azure_subscription_id
}

data "azurerm_subscription" "current" {}

data "azurerm_dns_zone" "public" {
  count               = var.create_public_cname ? 1 : 0
  name                = var.public_zone_name
  resource_group_name = var.public_zone_resource_group_name
}

locals {
  tags = merge(
    {
      project      = "multi-cloud-k8s"
      environment  = var.environment
      "managed-by" = "terraform"
      component    = "traffic-routing"
    },
    var.extra_tags,
  )

  profile_name = coalesce(var.profile_name, "mc-k8s-edge-profile")
  public_fqdn  = trimsuffix("${var.public_record_name}.${var.public_zone_name}", ".")
}

resource "azurerm_resource_group" "routing" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_traffic_manager_profile" "edge" {
  name                   = local.profile_name
  resource_group_name    = azurerm_resource_group.routing.name
  traffic_routing_method = "Weighted"
  profile_status         = "Enabled"
  tags                   = local.tags

  dns_config {
    relative_name = var.relative_name
    ttl           = var.dns_ttl
  }

  monitor_config {
    protocol                     = var.monitor_protocol
    port                         = var.monitor_port
    path                         = var.monitor_path
    interval_in_seconds          = var.monitor_interval_seconds
    timeout_in_seconds           = var.monitor_timeout_seconds
    tolerated_number_of_failures = var.monitor_tolerated_failures
    expected_status_code_ranges  = ["200-399"]

    custom_header {
      name  = "Host"
      value = local.public_fqdn
    }
  }
}

resource "azurerm_traffic_manager_external_endpoint" "gke" {
  name            = "gke-edge"
  profile_id      = azurerm_traffic_manager_profile.edge.id
  target          = var.gke_endpoint_fqdn
  weight          = var.gke_weight
  endpoint_status = "Enabled"
}

resource "azurerm_traffic_manager_external_endpoint" "aks" {
  name            = "aks-edge"
  profile_id      = azurerm_traffic_manager_profile.edge.id
  target          = var.aks_endpoint_fqdn
  weight          = var.aks_weight
  endpoint_status = "Enabled"
}

resource "azurerm_dns_cname_record" "public" {
  count               = var.create_public_cname ? 1 : 0
  name                = var.public_record_name
  zone_name           = data.azurerm_dns_zone.public[0].name
  resource_group_name = data.azurerm_dns_zone.public[0].resource_group_name
  ttl                 = var.dns_ttl
  record              = azurerm_traffic_manager_profile.edge.fqdn
  tags                = local.tags
}

# TODO: add a second profile for blue/green edge cutovers once I stop changing routes in place.
