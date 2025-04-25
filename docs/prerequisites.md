# Prerequisites for AKS Fleet Manager Project

## Azure Account Requirements
- **Azure Subscription** with active status and sufficient permissions
- **Azure Account** with Owner or Contributor role at the subscription level
- **Microsoft Entra ID** (formerly Azure AD) tenant where all clusters will reside

## Software Requirements
- **Terraform** version 1.0.0 or higher
- **Azure CLI** version 2.58.0 or higher
- **Fleet extension** for Azure CLI (`az extension add --name fleet`)
- **kubectl** for Kubernetes cluster management
- **kubelogin** for Azure Kubernetes authentication

## Environment Setup
- A development environment with the above tools installed
- Authentication configured for Azure CLI (`az login`)
- Proper subscription selected (`az account set --subscription <subscription_id>`)

## Required Permissions
The Azure identity used for deployment needs:
- **Microsoft.ContainerService/fleets/write** permissions to create Fleet Manager
- **Microsoft.ContainerService/managedClusters/write** permissions to create AKS clusters
- **Microsoft.ContainerService/fleets/members/write** permissions to join clusters to Fleet Manager
- **Microsoft.Network/virtualNetworks/write** permissions for networking resources
- **Microsoft.Resources/subscriptions/resourceGroups/write** permissions for resource group management

## Resource Quotas
- Sufficient VM quota in target regions for:
  - At least 8 VMs for the 4 AKS clusters (2 nodes per cluster minimum)
  - Standard_D2s_v3 and Standard_D4s_v3 VM sizes availability
- Sufficient IP address space for 3 virtual networks (10.0.0.0/16, 10.1.0.0/16, 10.2.0.0/16)

## Network Considerations
- Outbound internet access from deployment environment
- No network restrictions preventing peering between the virtual networks
- No conflicting IP address spaces in the target environment

## Additional Requirements
- Azure Front Door access and permissions if using the global routing feature
- Regional availability of AKS in East US and West Europe regions
- Appropriate Azure budget for running multiple AKS clusters
- Understanding of Kubernetes version support policy for Fleet Manager compatibility

## Post-Deployment Requirements
- Access to run Azure CLI commands for creating update groups
- Permissions to manage AKS clusters via Fleet Manager

## Optional
- DNS configuration if planning to set up custom domains later
- Azure Key Vault access for storing secrets if implementing a complete application stack
- Azure DevOps or GitHub Actions for CI/CD pipeline integration

---

**Note:** Before deploying, review the latest [Azure Kubernetes Fleet Manager documentation](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/) as feature availability and requirements may change.