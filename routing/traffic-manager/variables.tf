variable "name_prefix" {
  type        = string
  description = "Short prefix used for routing resources."
  default     = "mc-k8s"
}

variable "environment" {
  type        = string
  description = "Environment tag for the profile."
  default     = "dev"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group used for Azure Traffic Manager."
  default     = "mc-k8s-routing-rg"
}

variable "resource_group_location" {
  type        = string
  description = "Azure region for the resource group."
  default     = "eastus"
}

variable "profile_relative_name" {
  type        = string
  description = "DNS relative name for the Traffic Manager profile."
  default     = "mc-k8s-edge"
}

variable "dns_ttl" {
  type        = number
  description = "Traffic Manager DNS TTL in seconds."
  default     = 30
}

variable "health_probe_path" {
  type        = string
  description = "Path used by Traffic Manager to probe the public ingress."
  default     = "/healthz"
}

variable "probe_interval_seconds" {
  type        = number
  description = "Traffic Manager probe interval."
  default     = 10
}

variable "probe_timeout_seconds" {
  type        = number
  description = "Traffic Manager probe timeout."
  default     = 5
}

variable "tolerated_failures" {
  type        = number
  description = "Number of failed probes tolerated before failover."
  default     = 1
}

variable "gke_endpoint_fqdn" {
  type        = string
  description = "Public hostname for the GKE ingress gateway."
  default     = "gke-api.platform.haleops.net"
}

variable "aks_endpoint_fqdn" {
  type        = string
  description = "Public hostname for the AKS ingress gateway."
  default     = "aks-api.platform.haleops.net"
}

variable "gke_weight" {
  type        = number
  description = "Traffic weight for GKE."
  default     = 70
}

variable "aks_weight" {
  type        = number
  description = "Traffic weight for AKS."
  default     = 30
}

variable "shared_hostname" {
  type        = string
  description = "Friendly hostname that CNAMEs to the Traffic Manager profile."
  default     = "api.platform.haleops.net"
}
