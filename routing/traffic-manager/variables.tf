variable "azure_subscription_id" {
  type        = string
  description = "Azure subscription ID that owns the Traffic Manager profile."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for Traffic Manager resources."
  default     = "mc-k8s-edge-rg"
}

variable "location" {
  type        = string
  description = "Azure resource group location. Traffic Manager itself stays global."
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Environment tag value."
  default     = "dev"
}

variable "profile_name" {
  type        = string
  description = "Traffic Manager profile name."
  default     = null
}

variable "relative_name" {
  type        = string
  description = "DNS name prefix under trafficmanager.net."
  default     = "mc-k8s-edge"
}

variable "dns_ttl" {
  type        = number
  description = "Traffic Manager DNS TTL in seconds."
  default     = 30
}

variable "monitor_protocol" {
  type        = string
  description = "Health probe protocol."
  default     = "HTTP"
}

variable "monitor_path" {
  type        = string
  description = "HTTP path used by Traffic Manager health probes."
  default     = "/healthz"
}

variable "monitor_port" {
  type        = number
  description = "HTTP port used by Traffic Manager health probes."
  default     = 80
}

variable "monitor_interval_seconds" {
  type        = number
  description = "Traffic Manager probe interval."
  default     = 10
}

variable "monitor_timeout_seconds" {
  type        = number
  description = "Traffic Manager probe timeout."
  default     = 5
}

variable "monitor_tolerated_failures" {
  type        = number
  description = "How many failed probes I tolerate before the endpoint drops out."
  default     = 3
}

variable "public_zone_name" {
  type        = string
  description = "Azure DNS zone for the public hostname."
  default     = "platform.example.com"
}

variable "public_zone_resource_group_name" {
  type        = string
  description = "Resource group that owns the public Azure DNS zone."
  default     = "mc-k8s-dns-rg"
}

variable "public_record_name" {
  type        = string
  description = "Public hostname record name."
  default     = "api"
}

variable "create_public_cname" {
  type        = bool
  description = "Create the public CNAME in Azure DNS."
  default     = true
}

variable "gke_endpoint_fqdn" {
  type        = string
  description = "Public DNS name that resolves to the GKE ingress gateway."
}

variable "aks_endpoint_fqdn" {
  type        = string
  description = "Public DNS name that resolves to the AKS ingress gateway."
}

variable "gke_weight" {
  type        = number
  description = "Weighted routing value for the GKE endpoint."
  default     = 70
}

variable "aks_weight" {
  type        = number
  description = "Weighted routing value for the AKS endpoint."
  default     = 30
}

variable "extra_tags" {
  type        = map(string)
  description = "Extra tags merged into the default tag set."
  default     = {}
}
