output "gcp_project_number" {
  description = "Numeric GCP project number."
  value       = data.google_project.current.number
}

output "azure_subscription_id" {
  description = "Azure subscription ID from the active provider context."
  value       = data.azurerm_subscription.current.subscription_id
}

output "gke_cluster_id" {
  description = "GKE cluster resource ID."
  value       = module.gke.cluster_id
}

output "gke_cluster_endpoint" {
  description = "GKE control plane endpoint."
  value       = module.gke.endpoint
}

output "gke_ingress_public_ip" {
  description = "Reserved public IP for the future GKE ingress gateway."
  value       = module.gke.ingress_public_ip_address
}

output "gke_get_credentials" {
  description = "Command I use to pull GKE kubeconfig credentials."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${module.gke.location} --project ${var.gcp_project_id}"
}

output "aks_cluster_id" {
  description = "AKS cluster resource ID."
  value       = module.aks.cluster_id
}

output "aks_cluster_fqdn" {
  description = "AKS API server FQDN."
  value       = module.aks.fqdn
}

output "aks_ingress_public_ip" {
  description = "Reserved public IP for the future AKS ingress gateway."
  value       = module.aks.ingress_public_ip_address
}

output "aks_get_credentials" {
  description = "Command I use to pull AKS kubeconfig credentials."
  value       = "az aks get-credentials --resource-group ${module.aks.resource_group_name} --name ${module.aks.cluster_name} --overwrite-existing"
}

output "traffic_manager_fqdn" {
  description = "Traffic Manager FQDN."
  value       = module.dns.traffic_manager_fqdn
}

output "platform_hostname" {
  description = "Cloud DNS hostname that points to Traffic Manager."
  value       = module.dns.platform_hostname
}
