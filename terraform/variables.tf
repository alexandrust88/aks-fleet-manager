variable "primary_region" {
  description = "The primary Azure region for deployment"
  type        = string
  default     = "eastus"
}

variable "secondary_region" {
  description = "The secondary Azure region for deployment"
  type        = string
  default     = "westeurope"
}

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "aksfm"
}

variable "dev_node_count" {
  description = "Number of nodes in development AKS clusters"
  type        = number
  default     = 1
}

variable "prod_node_count" {
  description = "Number of nodes in production AKS clusters"
  type        = number
  default     = 1
}

variable "dev_node_vm_size" {
  description = "VM size for development AKS clusters"
  type        = string
  default     = "Standard_B2s"
}

variable "prod_node_vm_size" {
  description = "VM size for production AKS clusters"
  type        = string
  default     = "Standard_B2s"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS clusters (default: latest)"
  type        = string
  default     = null
}

variable "vnet_address_spaces" {
  description = "Address spaces for virtual networks"
  type        = map(string)
  default     = {
    fleet    = "10.0.0.0/16"
    eastus   = "10.1.0.0/16"
    westeu   = "10.2.0.0/16"
  }
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type        = map(string)
  default     = {
    fleet    = "10.0.1.0/24"
    eastus   = "10.1.1.0/24"
    westeu   = "10.2.1.0/24"
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {
    Environment = "Demo"
    ManagedBy   = "Terraform"
    Project     = "AKS Fleet Manager"
  }
}