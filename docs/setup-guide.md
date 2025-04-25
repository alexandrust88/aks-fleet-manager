# AKS Fleet Manager Setup Guide

This guide provides detailed instructions for setting up an Azure Kubernetes Fleet Manager with 4 AKS clusters (2 development, 2 production) across different regions.

## Deployment Steps

### 1. Prepare Your Environment

First, ensure you have all the [prerequisites](prerequisites.md) installed and configured:

```bash
# Clone the repository
git clone https://github.com/yourusername/aks-fleet-manager.git
cd aks-fleet-manager

# Setup required CLI tools
./scripts/setup-cli.sh

# Login to Azure
az login
az account set --subscription <SUBSCRIPTION_ID>
```

### 2. Configure Terraform Variables

Review and modify the variables in `terraform/variables.tf` to match your requirements:

```bash
cd terraform
```

You may want to create a `terraform.tfvars` file with your custom values:

```hcl
primary_region   = "eastus"
secondary_region = "westeurope"
resource_prefix  = "mycompany"
dev_node_count   = 2
prod_node_count  = 3
```

### 3. Deploy the Infrastructure

Initialize and apply the Terraform configuration:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

The deployment will create:
- Resource groups in each region
- Virtual networks with peering between regions
- 4 AKS clusters (2 dev, 2 prod) across regions
- Azure Kubernetes Fleet Manager
- Azure Front Door for global load balancing

### 4. Create Update Groups

After the infrastructure is deployed, create update groups for controlled cluster updates:

```bash
../scripts/create-update-groups.sh
```

This script uses the Azure CLI to create:
- A development update group with both dev clusters
- A production update group with both prod clusters

### 5. Connect to Your Clusters

You can access your AKS clusters using the following commands:

```bash
# East US Dev Cluster
az aks get-credentials --resource-group <EASTUS_RG> --name <EASTUS_DEV_CLUSTER>

# West Europe Dev Cluster
az aks get-credentials --resource-group <WESTEU_RG> --name <WESTEU_DEV_CLUSTER>

# East US Prod Cluster
az aks get-credentials --resource-group <EASTUS_RG> --name <EASTUS_PROD_CLUSTER>

# West Europe Prod Cluster
az aks get-credentials --resource-group <WESTEU_RG> --name <WESTEU_PROD_CLUSTER>
```

Replace the placeholders with the actual resource group and cluster names from your deployment.

## Managing Updates

To manage updates across your clusters:

1. **View Update Groups in Azure Portal**:
   - Navigate to your Fleet Manager resource
   - Select "Multi-cluster update" under Settings
   - View your update groups

2. **Create an Update Run**:
   - In the Azure Portal, select "Create a run"
   - Choose your update strategy (stages)
   - Select the Kubernetes version or node image to update
   - Start the update run

3. **Using Azure CLI for Updates**:
   ```bash
   # Create an update run
   az fleet updaterun create \
     --resource-group <FLEET_RG> \
     --fleet-name <FLEET_NAME> \
     --name run-1 \
     --upgrade-type Full \
     --kubernetes-version <VERSION> \
     --node-image-selection Latest

   # Start the update run
   az fleet updaterun start \
     --resource-group <FLEET_RG> \
     --fleet-name <FLEET_NAME> \
     --name run-1
   ```

## Clean Up

To remove all resources when they're no longer needed:

```bash
cd terraform
terraform destroy
```

## Troubleshooting

If you encounter issues:

1. **Deployment Failures**:
   - Check the Azure Activity Log for the specific resource
   - Review Terraform logs with `TF_LOG=DEBUG terraform apply`

2. **Update Group Creation Fails**:
   - Ensure the Fleet extension is installed: `az extension add --name fleet`
   - Verify member cluster names match the ones in the Fleet Manager

3. **Network Connectivity Issues**:
   - Verify VNet peering is properly configured and in "Connected" state
   - Check Network Security Groups for any blocking rules