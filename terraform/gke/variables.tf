variable "project_id" {
  description = "GCP project ID for the GKE resources."
  type        = string
}

variable "region" {
  description = "Region for GCP networking and the reserved ingress IP."
  type        = string
}

variable "zone" {
  description = "Zone for the GKE Standard cluster."
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
}

variable "network_name" {
  description = "VPC name."
  type        = string
}

variable "subnetwork_name" {
  description = "Subnet name."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR for the GKE nodes."
  type        = string
}

variable "pods_secondary_name" {
  description = "Secondary range name for pods."
  type        = string
}

variable "pods_secondary_cidr" {
  description = "Secondary range CIDR for pods."
  type        = string
}

variable "services_secondary_name" {
  description = "Secondary range name for services."
  type        = string
}

variable "services_secondary_cidr" {
  description = "Secondary range CIDR for services."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "Private control plane CIDR."
  type        = string
}

variable "node_machine_type" {
  description = "Machine type for the main node pool."
  type        = string
}

variable "min_nodes" {
  description = "Minimum node count."
  type        = number
}

variable "max_nodes" {
  description = "Maximum node count."
  type        = number
}

variable "release_channel" {
  description = "GKE release channel."
  type        = string
}

variable "gke_version" {
  description = "Optional GKE version pin."
  type        = string
  default     = null
  nullable    = true
}

variable "aks_source_cidr" {
  description = "AKS VNet CIDR used for cross-cloud Istio ports."
  type        = string
}

variable "labels" {
  description = "Common GCP labels."
  type        = map(string)
}

variable "tags" {
  description = "Common tag-style values used for names and output hints."
  type        = map(string)
}
