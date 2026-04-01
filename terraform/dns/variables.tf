variable "gcp_project_id" {
  description = "GCP project ID for Cloud DNS."
  type        = string
}

variable "gcp_zone_name" {
  description = "Cloud DNS managed zone resource name."
  type        = string
}

variable "public_dns_zone_name" {
  description = "Public DNS zone apex with a trailing dot."
  type        = string
}

variable "public_app_record_name" {
  description = "Record name users hit for the platform edge."
  type        = string
}

variable "gke_edge_record_name" {
  description = "Record name that maps to the GKE reserved ingress IP."
  type        = string
}

variable "gke_edge_ip_address" {
  description = "Reserved GKE ingress public IP address."
  type        = string
}

variable "azure_location" {
  description = "Azure region for the Traffic Manager resource group."
  type        = string
}

variable "azure_resource_group_name" {
  description = "Azure resource group name for the Traffic Manager profile."
  type        = string
}

variable "traffic_manager_profile_name" {
  description = "Traffic Manager profile resource name."
  type        = string
}

variable "traffic_manager_relative_name" {
  description = "Traffic Manager DNS relative name."
  type        = string
}

variable "aks_public_ip_id" {
  description = "Reserved AKS ingress public IP resource ID."
  type        = string
}

variable "gke_endpoint_weight" {
  description = "Traffic weight for the GKE endpoint."
  type        = number
}

variable "aks_endpoint_weight" {
  description = "Traffic weight for the AKS endpoint."
  type        = number
}

variable "labels" {
  description = "Common GCP labels."
  type        = map(string)
}

variable "tags" {
  description = "Common Azure tags."
  type        = map(string)
}
