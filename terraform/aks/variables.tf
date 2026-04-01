variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
}

variable "resource_group_name" {
  description = "AKS resource group name."
  type        = string
}

variable "node_resource_group_name" {
  description = "Node resource group name for AKS."
  type        = string
}

variable "location" {
  description = "Azure region for the AKS resources."
  type        = string
}

variable "vnet_name" {
  description = "AKS VNet name."
  type        = string
}

variable "subnet_name" {
  description = "AKS subnet name."
  type        = string
}

variable "route_table_name" {
  description = "Route table name for the AKS subnet."
  type        = string
}

variable "public_ip_name" {
  description = "Reserved public IP for the future AKS ingress gateway."
  type        = string
}

variable "vnet_cidr" {
  description = "AKS VNet CIDR."
  type        = string
}

variable "subnet_cidr" {
  description = "AKS subnet CIDR."
  type        = string
}

variable "pod_cidr" {
  description = "AKS overlay pod CIDR."
  type        = string
}

variable "service_cidr" {
  description = "AKS service CIDR."
  type        = string
}

variable "dns_service_ip" {
  description = "DNS service IP inside the AKS service CIDR."
  type        = string
}

variable "node_vm_size" {
  description = "VM size for the AKS system node pool."
  type        = string
}

variable "min_nodes" {
  description = "Minimum AKS node count."
  type        = number
}

variable "max_nodes" {
  description = "Maximum AKS node count."
  type        = number
}

variable "kubernetes_version" {
  description = "Optional AKS version pin."
  type        = string
  default     = null
  nullable    = true
}

variable "sku_tier" {
  description = "AKS pricing tier."
  type        = string
}

variable "support_plan" {
  description = "AKS support plan."
  type        = string
}

variable "gke_source_cidr" {
  description = "GKE subnet CIDR used for mesh ports in the NSG."
  type        = string
}

variable "tags" {
  description = "Common Azure tags."
  type        = map(string)
}
