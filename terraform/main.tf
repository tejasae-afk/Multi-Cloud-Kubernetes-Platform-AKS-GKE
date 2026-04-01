# I split the first applies on purpose because GKE takes longer and I don't want
# to wait on Azure every time I'm only touching one side.
# Step 1: terraform init
# Step 2: terraform apply -target=module.gke (~15min)
# Step 3: terraform apply -target=module.aks (~8min)
# Step 4: terraform apply (dns + remaining)

locals {
  common_tags = {
    project      = "multi-cloud-k8s"
    environment  = "dev"
    "managed-by" = "terraform"
  }

  common_labels = {
    project      = "multi-cloud-k8s"
    environment  = "dev"
    "managed-by" = "terraform"
  }

  public_dns_zone_name = endswith(var.public_dns_zone_name, ".") ? var.public_dns_zone_name : "${var.public_dns_zone_name}."
}

data "google_project" "current" {
  project_id = var.gcp_project_id
}

data "azurerm_subscription" "current" {}

provider "google" {
  project        = var.gcp_project_id
  region         = var.gcp_region
  default_labels = local.common_labels
}

provider "azurerm" {
  features {}

  subscription_id = var.azure_subscription_id
}

module "gke" {
  source = "./gke"

  project_id              = var.gcp_project_id
  region                  = var.gcp_region
  zone                    = var.gcp_zone
  cluster_name            = var.gke_cluster_name
  network_name            = var.gke_network_name
  subnetwork_name         = var.gke_subnetwork_name
  subnet_cidr             = var.gke_subnet_cidr
  pods_secondary_name     = var.gke_pods_secondary_name
  pods_secondary_cidr     = var.gke_pods_secondary_cidr
  services_secondary_name = var.gke_services_secondary_name
  services_secondary_cidr = var.gke_services_secondary_cidr
  master_ipv4_cidr_block  = var.gke_master_ipv4_cidr_block
  node_machine_type       = var.gke_node_machine_type
  min_nodes               = var.gke_min_nodes
  max_nodes               = var.gke_max_nodes
  release_channel         = var.gke_release_channel
  gke_version             = var.gke_version
  aks_source_cidr         = var.aks_vnet_cidr
  labels                  = local.common_labels
  tags                    = local.common_tags
}

module "aks" {
  source = "./aks"

  cluster_name             = var.aks_cluster_name
  resource_group_name      = var.aks_resource_group_name
  node_resource_group_name = var.aks_node_resource_group_name
  location                 = var.azure_location
  vnet_name                = var.aks_vnet_name
  subnet_name              = var.aks_subnet_name
  route_table_name         = var.aks_route_table_name
  public_ip_name           = var.aks_public_ip_name
  vnet_cidr                = var.aks_vnet_cidr
  subnet_cidr              = var.aks_subnet_cidr
  pod_cidr                 = var.aks_pod_cidr
  service_cidr             = var.aks_service_cidr
  dns_service_ip           = var.aks_dns_service_ip
  node_vm_size             = var.aks_node_vm_size
  min_nodes                = var.aks_min_nodes
  max_nodes                = var.aks_max_nodes
  kubernetes_version       = var.aks_kubernetes_version
  sku_tier                 = var.aks_sku_tier
  support_plan             = var.aks_support_plan
  gke_source_cidr          = var.gke_subnet_cidr
  tags                     = local.common_tags
}

module "dns" {
  source = "./dns"

  depends_on = [module.gke, module.aks]

  gcp_project_id                = var.gcp_project_id
  gcp_zone_name                 = var.gcp_dns_managed_zone_name
  public_dns_zone_name          = local.public_dns_zone_name
  public_app_record_name        = var.public_app_record_name
  gke_edge_record_name          = var.gke_edge_record_name
  gke_edge_ip_address           = module.gke.ingress_public_ip_address
  azure_location                = var.azure_location
  azure_resource_group_name     = var.azure_dns_resource_group_name
  traffic_manager_profile_name  = var.traffic_manager_profile_name
  traffic_manager_relative_name = var.traffic_manager_relative_name
  aks_public_ip_id              = module.aks.ingress_public_ip_id
  gke_endpoint_weight           = var.gke_endpoint_weight
  aks_endpoint_weight           = var.aks_endpoint_weight
  labels                        = local.common_labels
  tags                          = local.common_tags
}

# TODO: add a tiny wrapper script for targeted applies once I stop fat-fingering them at night.
