output "fleet_manager_id" {
  value       = azurerm_kubernetes_fleet_manager.fleet_manager.id
  description = "The ID of the AKS Fleet Manager"
}

output "fleet_manager_name" {
  value       = azurerm_kubernetes_fleet_manager.fleet_manager.name
  description = "The name of the AKS Fleet Manager"
}

output "dev_clusters" {
  value = {
    eastus = {
      id   = azurerm_kubernetes_cluster.aks_eastus_dev1.id
      name = azurerm_kubernetes_cluster.aks_eastus_dev1.name
      fqdn = azurerm_kubernetes_cluster.aks_eastus_dev1.fqdn
    }
    westeurope = {
      id   = azurerm_kubernetes_cluster.aks_westeu_dev2.id
      name = azurerm_kubernetes_cluster.aks_westeu_dev2.name
      fqdn = azurerm_kubernetes_cluster.aks_westeu_dev2.fqdn
    }
  }
  description = "Development AKS clusters information"
  sensitive   = true
}

output "prod_clusters" {
  value = {
    eastus = {
      id   = azurerm_kubernetes_cluster.aks_eastus_prod1.id
      name = azurerm_kubernetes_cluster.aks_eastus_prod1.name
      fqdn = azurerm_kubernetes_cluster.aks_eastus_prod1.fqdn
    }
    westeurope = {
      id   = azurerm_kubernetes_cluster.aks_westeu_prod2.id
      name = azurerm_kubernetes_cluster.aks_westeu_prod2.name
      fqdn = azurerm_kubernetes_cluster.aks_westeu_prod2.fqdn
    }
  }
  description = "Production AKS clusters information"
  sensitive   = true
}

output "afd_endpoint_hostname" {
  value       = azurerm_cdn_frontdoor_endpoint.afd_endpoint.host_name
  description = "Azure Front Door endpoint hostname"
}

output "resource_group_names" {
  value = {
    fleet_manager = azurerm_resource_group.fleet_rg.name
    eastus_aks    = azurerm_resource_group.eastus_rg.name
    westeu_aks    = azurerm_resource_group.westeu_rg.name
  }
  description = "Names of the created resource groups"
}

output "update_groups_instructions" {
  value = <<-EOT
  # After applying this Terraform configuration, run the following Azure CLI commands to create update groups:
  
  # First, install the fleet extension if not already installed
  az extension add --name fleet
  
  # Create development update group
  az fleet updategroup create --resource-group ${azurerm_resource_group.fleet_rg.name} \\
    --fleet-name ${azurerm_kubernetes_fleet_manager.fleet_manager.name} \\
    --name development-update-group \\
    --type Rolling \\
    --cluster-names eastus-dev1-member westeu-dev2-member
  
  # Create production update group
  az fleet updategroup create --resource-group ${azurerm_resource_group.fleet_rg.name} \\
    --fleet-name ${azurerm_kubernetes_fleet_manager.fleet_manager.name} \\
    --name production-update-group \\
    --type Rolling \\
    --cluster-names eastus-prod1-member westeu-prod2-member
  EOT
  description = "Azure CLI commands to create update groups after Terraform deployment"
}

output "kubeconfig_commands" {
  value = <<-EOT
  # Commands to get kubeconfig for each cluster:
  
  # East US Dev Cluster
  az aks get-credentials --resource-group ${azurerm_resource_group.eastus_rg.name} --name ${azurerm_kubernetes_cluster.aks_eastus_dev1.name}
  
  # West Europe Dev Cluster
  az aks get-credentials --resource-group ${azurerm_resource_group.westeu_rg.name} --name ${azurerm_kubernetes_cluster.aks_westeu_dev2.name}
  
  # East US Prod Cluster
  az aks get-credentials --resource-group ${azurerm_resource_group.eastus_rg.name} --name ${azurerm_kubernetes_cluster.aks_eastus_prod1.name}
  
  # West Europe Prod Cluster
  az aks get-credentials --resource-group ${azurerm_resource_group.westeu_rg.name} --name ${azurerm_kubernetes_cluster.aks_westeu_prod2.name}
  EOT
  description = "Commands to get kubeconfig for each AKS cluster"
}

output "application_urls" {
  value = {
    dev_url = "https://${azurerm_cdn_frontdoor_endpoint.afd_endpoint.host_name}/dev"
    prod_url = "https://${azurerm_cdn_frontdoor_endpoint.afd_endpoint.host_name}/prod"
  }
  description = "URLs to access the dev and prod applications via Azure Front Door"
}