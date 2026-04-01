output "cluster_id" {
  description = "AKS cluster ID."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  description = "AKS resource group name."
  value       = azurerm_resource_group.this.name
}

output "fqdn" {
  description = "AKS API server FQDN."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "node_resource_group" {
  description = "AKS node resource group."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "ingress_public_ip_id" {
  description = "Reserved AKS ingress public IP resource ID."
  value       = azurerm_public_ip.ingress.id
}

output "ingress_public_ip_address" {
  description = "Reserved AKS ingress public IP address."
  value       = azurerm_public_ip.ingress.ip_address
}

output "oidc_issuer_url" {
  description = "AKS OIDC issuer URL."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "cluster_identity_principal_id" {
  description = "Principal ID for the AKS user-assigned identity."
  value       = azurerm_user_assigned_identity.cluster.principal_id
}
