output "cluster_id" {
  description = "GKE cluster ID."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "GKE cluster location."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "GKE API endpoint."
  value       = google_container_cluster.this.endpoint
}

output "network_name" {
  description = "GKE VPC name."
  value       = google_compute_network.this.name
}

output "subnetwork_name" {
  description = "GKE subnet name."
  value       = google_compute_subnetwork.this.name
}

output "ingress_public_ip_address" {
  description = "Reserved GKE ingress public IP."
  value       = google_compute_address.ingress.address
}

output "node_service_account_email" {
  description = "Node pool service account email."
  value       = google_service_account.gke_nodes.email
}

output "workload_identity_service_account_email" {
  description = "Workload identity service account email."
  value       = google_service_account.workload_identity.email
}
