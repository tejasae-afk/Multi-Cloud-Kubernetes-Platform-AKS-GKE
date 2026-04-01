variable "gcp_project_id" {
  description = "GCP project ID for the GKE and Cloud DNS resources."
  type        = string
}

variable "gcp_region" {
  description = "Region for shared GCP networking resources."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "Zone for the zonal GKE Standard cluster."
  type        = string
  default     = "us-central1-a"
}

variable "azure_subscription_id" {
  description = "Azure subscription ID. Leave this null if the Azure CLI context is already set the way you want."
  type        = string
  default     = null
  nullable    = true
}

variable "azure_location" {
  description = "Azure region for AKS and Traffic Manager resource groups."
  type        = string
  default     = "eastus"
}

variable "gke_cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "mc-k8s-gke-cluster"
}

variable "gke_network_name" {
  description = "VPC name for GKE."
  type        = string
  default     = "mc-k8s-gke-vpc"
}

variable "gke_subnetwork_name" {
  description = "Subnet name for GKE nodes."
  type        = string
  default     = "mc-k8s-gke-subnet"
}

variable "gke_subnet_cidr" {
  description = "Primary subnet CIDR for GKE nodes."
  type        = string
  default     = "10.0.0.0/16"
}

variable "gke_pods_secondary_name" {
  description = "Secondary range name for GKE pods."
  type        = string
  default     = "mc-k8s-gke-pods"
}

variable "gke_pods_secondary_cidr" {
  description = "Secondary CIDR for GKE pods."
  type        = string
  default     = "10.10.0.0/14"
}

variable "gke_services_secondary_name" {
  description = "Secondary range name for GKE services."
  type        = string
  default     = "mc-k8s-gke-services"
}

variable "gke_services_secondary_cidr" {
  description = "Secondary CIDR for GKE services."
  type        = string
  default     = "10.20.0.0/20"
}

variable "gke_master_ipv4_cidr_block" {
  description = "Private control plane CIDR for GKE."
  type        = string
  default     = "172.16.0.0/28"
}

variable "gke_node_machine_type" {
  description = "Machine type for the main GKE node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "gke_min_nodes" {
  description = "Minimum node count for the main GKE node pool."
  type        = number
  default     = 2
}

variable "gke_max_nodes" {
  description = "Maximum node count for the main GKE node pool."
  type        = number
  default     = 5
}

variable "gke_release_channel" {
  description = "Release channel for GKE."
  type        = string
  default     = "REGULAR"
}

variable "gke_version" {
  description = "Optional GKE version pin. I leave this null by default so the repo still applies after old patches age out."
  type        = string
  default     = null
  nullable    = true
}

variable "aks_cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "mc-k8s-aks"
}

variable "aks_resource_group_name" {
  description = "Resource group name for AKS."
  type        = string
  default     = "mc-k8s-aks-rg"
}

variable "aks_node_resource_group_name" {
  description = "Dedicated node resource group name for AKS. It must not exist before the cluster is created."
  type        = string
  default     = "mc-k8s-aks-nodes-rg"
}

variable "aks_vnet_name" {
  description = "VNet name for AKS."
  type        = string
  default     = "mc-k8s-aks-vnet"
}

variable "aks_subnet_name" {
  description = "Subnet name for AKS nodes."
  type        = string
  default     = "mc-k8s-aks-subnet"
}

variable "aks_route_table_name" {
  description = "Route table name for the AKS subnet."
  type        = string
  default     = "mc-k8s-aks-rt"
}

variable "aks_public_ip_name" {
  description = "Reserved public IP for the future AKS ingress gateway."
  type        = string
  default     = "mc-k8s-aks-ingress-ip"
}

variable "aks_vnet_cidr" {
  description = "VNet CIDR for AKS."
  type        = string
  default     = "10.1.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "Subnet CIDR for AKS worker nodes."
  type        = string
  default     = "10.1.0.0/20"
}

variable "aks_pod_cidr" {
  description = "Pod CIDR used by Azure CNI Overlay."
  type        = string
  default     = "172.18.0.0/16"
}

variable "aks_service_cidr" {
  description = "Service CIDR used by AKS."
  type        = string
  default     = "172.19.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "Cluster DNS service IP inside the AKS service CIDR."
  type        = string
  default     = "172.19.0.10"
}

variable "aks_node_vm_size" {
  description = "VM size for the AKS system node pool."
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aks_min_nodes" {
  description = "Minimum node count for the AKS system node pool."
  type        = number
  default     = 2
}

variable "aks_max_nodes" {
  description = "Maximum node count for the AKS system node pool."
  type        = number
  default     = 5
}

variable "aks_kubernetes_version" {
  description = "Optional AKS version pin. Leave this null for the current recommended GA version."
  type        = string
  default     = null
  nullable    = true
}

variable "aks_sku_tier" {
  description = "AKS pricing tier."
  type        = string
  default     = "Standard"
}

variable "aks_support_plan" {
  description = "AKS support plan."
  type        = string
  default     = "KubernetesOfficial"
}

variable "gcp_dns_managed_zone_name" {
  description = "Internal Cloud DNS managed zone name."
  type        = string
  default     = "mc-k8s-public-zone"
}

variable "public_dns_zone_name" {
  description = "Public DNS zone name. Use the zone apex, with or without the trailing dot."
  type        = string
}

variable "public_app_record_name" {
  description = "Record name that users hit for the platform edge."
  type        = string
  default     = "platform"
}

variable "gke_edge_record_name" {
  description = "Record name that points to the reserved GKE ingress IP."
  type        = string
  default     = "gke-edge"
}

variable "azure_dns_resource_group_name" {
  description = "Azure resource group that holds the Traffic Manager profile."
  type        = string
  default     = "mc-k8s-dns-rg"
}

variable "traffic_manager_profile_name" {
  description = "Traffic Manager profile resource name."
  type        = string
  default     = "mc-k8s-traffic"
}

variable "traffic_manager_relative_name" {
  description = "Traffic Manager DNS relative name. This needs to stay globally unique inside trafficmanager.net."
  type        = string
}

variable "gke_endpoint_weight" {
  description = "Traffic weight for the GKE endpoint in Traffic Manager."
  type        = number
  default     = 50
}

variable "aks_endpoint_weight" {
  description = "Traffic weight for the AKS endpoint in Traffic Manager."
  type        = number
  default     = 50
}
