# Configure the Azure Provider
provider "azurerm" {
  features {}
}

# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for resource naming and configuration
locals {
  resource_suffix        = random_string.suffix.result
  fleet_rg_name          = "fleet-manager-rg-${local.resource_suffix}"
  eastus_rg_name         = "aks-eastus-rg-${local.resource_suffix}"
  westeurope_rg_name     = "aks-westeu-rg-${local.resource_suffix}"
  fleet_name             = "fleet-${local.resource_suffix}"
  
  # AKS cluster names
  aks_eastus_dev1_name    = "aks-eastus-dev1-${local.resource_suffix}"
  aks_eastus_prod1_name   = "aks-eastus-prod1-${local.resource_suffix}"
  aks_westeu_dev2_name    = "aks-westeu-dev2-${local.resource_suffix}"
  aks_westeu_prod2_name   = "aks-westeu-prod2-${local.resource_suffix}"
  
  afd_name               = "afd-${local.resource_suffix}"

  # Azure regions
  primary_region         = var.primary_region
  secondary_region       = var.secondary_region

  # Network configuration
  vnet_fleet_name        = "fleet-vnet"
  vnet_fleet_cidr        = var.vnet_address_spaces.fleet
  subnet_fleet_name      = "fleet-subnet"
  subnet_fleet_cidr      = var.subnet_address_prefixes.fleet

  vnet_eastus_name       = "eastus-vnet"
  vnet_eastus_cidr       = var.vnet_address_spaces.eastus
  subnet_eastus_name     = "eastus-subnet"
  subnet_eastus_cidr     = var.subnet_address_prefixes.eastus

  vnet_westeu_name       = "westeu-vnet"
  vnet_westeu_cidr       = var.vnet_address_spaces.westeu
  subnet_westeu_name     = "westeu-subnet" 
  subnet_westeu_cidr     = var.subnet_address_prefixes.westeu

  # AKS configuration
  dev_node_count         = var.dev_node_count
  prod_node_count        = var.prod_node_count
  dev_node_vm_size       = var.dev_node_vm_size
  prod_node_vm_size      = var.prod_node_vm_size

  # Tags
  common_tags = var.tags
  
  dev_tags = merge(var.tags, {
    Environment = "Development"
  })
  
  prod_tags = merge(var.tags, {
    Environment = "Production"
  })
}

# Create Resource Groups
resource "azurerm_resource_group" "fleet_rg" {
  name     = local.fleet_rg_name
  location = local.primary_region
  tags     = local.common_tags
}

resource "azurerm_resource_group" "eastus_rg" {
  name     = local.eastus_rg_name
  location = local.primary_region
  tags     = local.common_tags
}

resource "azurerm_resource_group" "westeu_rg" {
  name     = local.westeurope_rg_name
  location = local.secondary_region
  tags     = local.common_tags
}

# Create Virtual Networks and Subnets
# Fleet Manager VNet and Subnet
resource "azurerm_virtual_network" "fleet_vnet" {
  name                = local.vnet_fleet_name
  resource_group_name = azurerm_resource_group.fleet_rg.name
  location            = azurerm_resource_group.fleet_rg.location
  address_space       = [local.vnet_fleet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "fleet_subnet" {
  name                 = local.subnet_fleet_name
  resource_group_name  = azurerm_resource_group.fleet_rg.name
  virtual_network_name = azurerm_virtual_network.fleet_vnet.name
  address_prefixes     = [local.subnet_fleet_cidr]
}

# East US VNet and Subnet
resource "azurerm_virtual_network" "eastus_vnet" {
  name                = local.vnet_eastus_name
  resource_group_name = azurerm_resource_group.eastus_rg.name
  location            = azurerm_resource_group.eastus_rg.location
  address_space       = [local.vnet_eastus_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "eastus_subnet" {
  name                 = local.subnet_eastus_name
  resource_group_name  = azurerm_resource_group.eastus_rg.name
  virtual_network_name = azurerm_virtual_network.eastus_vnet.name
  address_prefixes     = [local.subnet_eastus_cidr]
}

# West Europe VNet and Subnet
resource "azurerm_virtual_network" "westeu_vnet" {
  name                = local.vnet_westeu_name
  resource_group_name = azurerm_resource_group.westeu_rg.name
  location            = azurerm_resource_group.westeu_rg.location
  address_space       = [local.vnet_westeu_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "westeu_subnet" {
  name                 = local.subnet_westeu_name
  resource_group_name  = azurerm_resource_group.westeu_rg.name
  virtual_network_name = azurerm_virtual_network.westeu_vnet.name
  address_prefixes     = [local.subnet_westeu_cidr]
}

# Create VNet Peering between regions
# Fleet to East US
resource "azurerm_virtual_network_peering" "fleet_to_eastus" {
  name                      = "fleet-to-eastus"
  resource_group_name       = azurerm_resource_group.fleet_rg.name
  virtual_network_name      = azurerm_virtual_network.fleet_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.eastus_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "eastus_to_fleet" {
  name                      = "eastus-to-fleet"
  resource_group_name       = azurerm_resource_group.eastus_rg.name
  virtual_network_name      = azurerm_virtual_network.eastus_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.fleet_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# Fleet to West Europe
resource "azurerm_virtual_network_peering" "fleet_to_westeu" {
  name                      = "fleet-to-westeu"
  resource_group_name       = azurerm_resource_group.fleet_rg.name
  virtual_network_name      = azurerm_virtual_network.fleet_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.westeu_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "westeu_to_fleet" {
  name                      = "westeu-to-fleet"
  resource_group_name       = azurerm_resource_group.westeu_rg.name
  virtual_network_name      = azurerm_virtual_network.westeu_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.fleet_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# East US to West Europe
resource "azurerm_virtual_network_peering" "eastus_to_westeu" {
  name                      = "eastus-to-westeu"
  resource_group_name       = azurerm_resource_group.eastus_rg.name
  virtual_network_name      = azurerm_virtual_network.eastus_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.westeu_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "westeu_to_eastus" {
  name                      = "westeu-to-eastus"
  resource_group_name       = azurerm_resource_group.westeu_rg.name
  virtual_network_name      = azurerm_virtual_network.westeu_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.eastus_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# Data source for the latest Kubernetes version
data "azurerm_kubernetes_service_versions" "current" {
  location = local.primary_region
}

# Create AKS clusters - 2 DEV and 2 PROD across regions
# East US DEV AKS Cluster
resource "azurerm_kubernetes_cluster" "aks_eastus_dev1" {
  name                = local.aks_eastus_dev1_name
  resource_group_name = azurerm_resource_group.eastus_rg.name
  location            = azurerm_resource_group.eastus_rg.location
  dns_prefix          = "aks-eastus-dev1-${local.resource_suffix}"
  kubernetes_version  = var.kubernetes_version != null ? var.kubernetes_version : data.azurerm_kubernetes_service_versions.current.latest_version
  
  default_node_pool {
    name           = "default"
    node_count     = local.dev_node_count
    vm_size        = local.dev_node_vm_size
    vnet_subnet_id = azurerm_subnet.eastus_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.1.0.10"
    service_cidr   = "10.1.0.0/24"
  }

  tags = merge(
    local.dev_tags,
    {
      Region = local.primary_region
    }
  )
}

# East US PROD AKS Cluster
resource "azurerm_kubernetes_cluster" "aks_eastus_prod1" {
  name                = local.aks_eastus_prod1_name
  resource_group_name = azurerm_resource_group.eastus_rg.name
  location            = azurerm_resource_group.eastus_rg.location
  dns_prefix          = "aks-eastus-prod1-${local.resource_suffix}"
  kubernetes_version  = var.kubernetes_version != null ? var.kubernetes_version : data.azurerm_kubernetes_service_versions.current.latest_version
  
  default_node_pool {
    name           = "default"
    node_count     = local.prod_node_count
    vm_size        = local.prod_node_vm_size
    vnet_subnet_id = azurerm_subnet.eastus_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.1.0.20"
    service_cidr   = "10.1.0.0/24"
  }

  tags = merge(
    local.prod_tags,
    {
      Region = local.primary_region
    }
  )
}

# West Europe DEV AKS Cluster
resource "azurerm_kubernetes_cluster" "aks_westeu_dev2" {
  name                = local.aks_westeu_dev2_name
  resource_group_name = azurerm_resource_group.westeu_rg.name
  location            = azurerm_resource_group.westeu_rg.location
  dns_prefix          = "aks-westeu-dev2-${local.resource_suffix}"
  kubernetes_version  = var.kubernetes_version != null ? var.kubernetes_version : data.azurerm_kubernetes_service_versions.current.latest_version
  
  default_node_pool {
    name           = "default"
    node_count     = local.dev_node_count
    vm_size        = local.dev_node_vm_size
    vnet_subnet_id = azurerm_subnet.westeu_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.2.0.10"
    service_cidr   = "10.2.0.0/24"
  }

  tags = merge(
    local.dev_tags,
    {
      Region = local.secondary_region
    }
  )
}

# West Europe PROD AKS Cluster
resource "azurerm_kubernetes_cluster" "aks_westeu_prod2" {
  name                = local.aks_westeu_prod2_name
  resource_group_name = azurerm_resource_group.westeu_rg.name
  location            = azurerm_resource_group.westeu_rg.location
  dns_prefix          = "aks-westeu-prod2-${local.resource_suffix}"
  kubernetes_version  = var.kubernetes_version != null ? var.kubernetes_version : data.azurerm_kubernetes_service_versions.current.latest_version
  
  default_node_pool {
    name           = "default"
    node_count     = local.prod_node_count
    vm_size        = local.prod_node_vm_size
    vnet_subnet_id = azurerm_subnet.westeu_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.2.0.20"
    service_cidr   = "10.2.0.0/24"
  }

  tags = merge(
    local.prod_tags,
    {
      Region = local.secondary_region
    }
  )
}

# Create AKS Fleet Manager
resource "azurerm_kubernetes_fleet_manager" "fleet_manager" {
  name                = local.fleet_name
  resource_group_name = azurerm_resource_group.fleet_rg.name
  location            = azurerm_resource_group.fleet_rg.location
  
  tags = local.common_tags
}

# Register AKS clusters with Fleet Manager
resource "azurerm_kubernetes_fleet_member" "aks_eastus_dev1_member" {
  name                   = "eastus-dev1-member"
  kubernetes_fleet_id    = azurerm_kubernetes_fleet_manager.fleet_manager.id
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.aks_eastus_dev1.id
  group                  = "development"
}

resource "azurerm_kubernetes_fleet_member" "aks_eastus_prod1_member" {
  name                   = "eastus-prod1-member"
  kubernetes_fleet_id    = azurerm_kubernetes_fleet_manager.fleet_manager.id
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.aks_eastus_prod1.id
  group                  = "production"
}

resource "azurerm_kubernetes_fleet_member" "aks_westeu_dev2_member" {
  name                   = "westeu-dev2-member"
  kubernetes_fleet_id    = azurerm_kubernetes_fleet_manager.fleet_manager.id
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.aks_westeu_dev2.id
  group                  = "development"
}

resource "azurerm_kubernetes_fleet_member" "aks_westeu_prod2_member" {
  name                   = "westeu-prod2-member"
  kubernetes_fleet_id    = azurerm_kubernetes_fleet_manager.fleet_manager.id
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.aks_westeu_prod2.id
  group                  = "production"
}

# Note: Update groups must be created using Azure CLI as they're not directly supported in Terraform

# Create Azure Front Door for global load balancing
# resource "azurerm_cdn_frontdoor_profile" "afd_profile" {
#   name                = local.afd_name
#   resource_group_name = azurerm_resource_group.fleet_rg.name
#   sku_name            = "Standard_AzureFrontDoor"

#   tags = local.common_tags
# }

# resource "azurerm_cdn_frontdoor_endpoint" "afd_endpoint" {
#   name                     = "aks-fleet-endpoint"
#   cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id
#   enabled                  = true
# }

# # Create origin groups for dev and prod environments
# resource "azurerm_cdn_frontdoor_origin_group" "dev_origin_group" {
#   name                     = "dev-origin-group"
#   cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id
  
#   load_balancing {
#     sample_size                 = 4
#     successful_samples_required = 2
#     additional_latency_in_milliseconds = 50
#   }

#   health_probe {
#     path                = "/"
#     protocol            = "Http"
#     interval_in_seconds = 60
#   }
# }

# resource "azurerm_cdn_frontdoor_origin_group" "prod_origin_group" {
#   name                     = "prod-origin-group"
#   cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id
  
#   load_balancing {
#     sample_size                 = 4
#     successful_samples_required = 2
#     additional_latency_in_milliseconds = 50
#   }

#   health_probe {
#     path                = "/"
#     protocol            = "Http"
#     interval_in_seconds = 60
#   }
# }

# # Create origins for all clusters
# # We'll use placeholders for the ingress IPs
# resource "azurerm_cdn_frontdoor_origin" "dev_eastus_origin" {
#   name                           = "dev-eastus"
#   cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.dev_origin_group.id
#   enabled                        = true
  
#   host_name                      = "dev-eastus-placeholder-ip.nip.io"
#   http_port                      = 80
#   https_port                     = 443
#   origin_host_header             = azurerm_kubernetes_cluster.aks_eastus_dev1.fqdn
#   priority                       = 1
#   weight                         = 1000
#   certificate_name_check_enabled = true
# }

# resource "azurerm_cdn_frontdoor_origin" "dev_westeu_origin" {
#   name                           = "dev-westeu"
#   cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.dev_origin_group.id
#   enabled                        = true
  
#   host_name                      = "dev-westeu-placeholder-ip.nip.io"
#   http_port                      = 80
#   https_port                     = 443
#   origin_host_header             = azurerm_kubernetes_cluster.aks_westeu_dev2.fqdn
#   priority                       = 1
#   weight                         = 1000
#   certificate_name_check_enabled = true
# }

# resource "azurerm_cdn_frontdoor_origin" "prod_eastus_origin" {
#   name                           = "prod-eastus"
#   cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.prod_origin_group.id
#   enabled                        = true
  
#   host_name                      = "prod-eastus-placeholder-ip.nip.io"
#   http_port                      = 80
#   https_port                     = 443
#   origin_host_header             = azurerm_kubernetes_cluster.aks_eastus_prod1.fqdn
#   priority                       = 1
#   weight                         = 1000
#   certificate_name_check_enabled = true
# }

# resource "azurerm_cdn_frontdoor_origin" "prod_westeu_origin" {
#   name                           = "prod-westeu"
#   cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.prod_origin_group.id
#   enabled                        = true
  
#   host_name                      = "prod-westeu-placeholder-ip.nip.io"
#   http_port                      = 80
#   https_port                     = 443
#   origin_host_header             = azurerm_kubernetes_cluster.aks_westeu_prod2.fqdn
#   priority                       = 1
#   weight                         = 1000
#   certificate_name_check_enabled = true
# }

# # Create routes for dev and prod with path-based routing
# resource "azurerm_cdn_frontdoor_route" "dev_route" {
#   name                          = "dev-route"
#   cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.afd_endpoint.id
#   cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.dev_origin_group.id
#   cdn_frontdoor_origin_ids      = [
#     azurerm_cdn_frontdoor_origin.dev_eastus_origin.id,
#     azurerm_cdn_frontdoor_origin.dev_westeu_origin.id
#   ]
  
#   patterns_to_match     = ["/dev/*"]
#   supported_protocols   = ["Http", "Https"]
#   forwarding_protocol   = "HttpOnly"
#   link_to_default_domain = true
# }

# resource "azurerm_cdn_frontdoor_route" "prod_route" {
#   name                          = "prod-route"
#   cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.afd_endpoint.id
#   cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.prod_origin_group.id
#   cdn_frontdoor_origin_ids      = [
#     azurerm_cdn_frontdoor_origin.prod_eastus_origin.id,
#     azurerm_cdn_frontdoor_origin.prod_westeu_origin.id
#   ]
  
#   patterns_to_match     = ["/prod/*"]
#   supported_protocols   = ["Http", "Https"]
#   forwarding_protocol   = "HttpOnly"
#   link_to_default_domain = true
# }