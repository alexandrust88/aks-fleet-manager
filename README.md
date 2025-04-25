# Azure Kubernetes Fleet Manager

This repository contains Terraform configurations and scripts to set up an Azure Kubernetes Fleet Manager with 4 AKS clusters - 2 for development and 2 for production environments across different regions.

## Architecture

The architecture includes:
- 4 AKS clusters (2 dev, 2 prod) across East US and West Europe regions
- Azure Kubernetes Fleet Manager for centralized management
- Network peering between regions
- Front Door for global load balancing
- Update groups for controlled cluster updates
- Architecture Diagram [https://github.com/saswatmohanty01/aks-fleet-manager/blob/main/architecture-diagrams/AKS_Fleet_Manager_Architecture.png]

## Prerequisites

Before you begin, ensure you have all the [prerequisites](docs/prerequisites.md) in place.

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/aks-fleet-manager.git
   cd aks-fleet-manager
   ```

2. Install the required tools:
   ```bash
   ./scripts/setup-cli.sh
   ```

3. Initialize Terraform:
   ```bash
   cd terraform
   terraform init
   ```

4. Review and modify the variables in `terraform/variables.tf` as needed.

5. Deploy the infrastructure:
   ```bash
   terraform apply -auto-approve
   ```

6. After deployment, create update groups using the script:
   ```bash
   ../scripts/create-update-groups.sh
   ```
   
**Known_Issue**. **Manual Step in Azure FrontDoor**
   - Get the terraform output for all four AKS clusters service endpoint IP addresses. You can get it from step 3 using kubectl get svc for all four clusters.
   - There is a bug, which does not allow to update the service IP addresses for each AKS cluster in Azure Frontdoor->Origin Groups
   - Manually update the IP addresses for Dev and Prod AKS cluster service IP addresses. Go to Azure portal->Azure Front door->Settings->Origin Groups->dev-origin-group
   - Manually update the IP addresses for Dev and Prod AKS cluster service IP addresses. Go to Azure portal->Azure Front door->Settings->Origin Groups->prod-origin-group 

## Detailed Setup

For detailed instructions, refer to the [Setup Guide](docs/setup-guide.md).

## Key Features

- **Multi-region Deployment**: AKS clusters in East US and West Europe
- **Environment Separation**: Dedicated clusters for development and production
- **Centralized Management**: Fleet Manager for unified administration
- **Controlled Updates**: Update groups for staged rollouts (created via Azure CLI)
- **Global Routing**: Azure Front Door for global traffic distribution
- **Network Connectivity**: Full VNet peering between all regions

## Known Limitations

- **Resource Type Support**: The Azure Terraform provider doesn't directly support update groups for Fleet Manager, so these must be created with Azure CLI after deployment
- **Provider Configuration**: Ensure you don't have duplicate provider blocks across Terraform files
- **API Versioning**: The Fleet Manager resource types are continuously evolving, so check for the latest provider version

## Troubleshooting

If you encounter issues during deployment:

- **Provider Conflicts**: Ensure you don't have duplicate provider blocks in `main.tf` and `versions.tf`
- **Resource Type Errors**: Verify you're using the correct resource type names (`azurerm_kubernetes_fleet_manager` instead of `azurerm_fleet_manager`)
- **Update Group Creation**: Update groups must be created with Azure CLI after the infrastructure is deployed

## Post-Deployment Tasks

After deploying the infrastructure, you'll need to:

1. Create update groups for controlled cluster updates
2. Configure your Kubernetes applications for deployment
3. Set up CI/CD pipelines for application deployment

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
