locals {
  dns_prefix    = "mck8saks"
  identity_name = "mc-k8s-aks-identity"
  nsg_name      = "mc-k8s-aks-nsg"
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_route_table" "this" {
  name                = var.route_table_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_route_table_association" "this" {
  subnet_id      = azurerm_subnet.this.id
  route_table_id = azurerm_route_table.this.id
}

resource "azurerm_public_ip" "ingress" {
  name                = var.public_ip_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  support_plan        = var.support_plan
  node_resource_group = var.node_resource_group_name

  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  azure_policy_enabled              = false
  node_os_upgrade_channel           = "NodeImage"

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    type                        = "VirtualMachineScaleSets"
    vnet_subnet_id              = azurerm_subnet.this.id
    auto_scaling_enabled        = true
    node_count                  = var.min_nodes
    min_count                   = var.min_nodes
    max_count                   = var.max_nodes
    orchestrator_version        = var.kubernetes_version
    temporary_name_for_rotation = "tempsys01"
    os_disk_size_gb             = 128
    os_disk_type                = "Managed"
    os_sku                      = "Ubuntu2204"
    max_pods                    = 110
    tags                        = var.tags

    node_labels = {
      cloud = "aks"
      pool  = "system"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "azure"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  auto_scaler_profile {
    balance_similar_node_groups                   = true
    daemonset_eviction_for_occupied_nodes_enabled = true
    expander                                      = "least-waste"
    skip_nodes_with_system_pods                   = false
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  depends_on = [
    azurerm_role_assignment.subnet_network_contributor,
    azurerm_role_assignment.public_ip_network_contributor
  ]

  # TODO: split system and workload pools once Istio and Prometheus start fighting for headroom.
}
