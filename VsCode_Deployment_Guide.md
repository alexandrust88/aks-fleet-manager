# End-to-End Deployment Guide for AKS Fleet Manager in VS Code

This guide walks through the complete process of deploying the AKS Fleet Manager and multiple AKS clusters using Visual Studio Code, including the demo applications.

## Prerequisites Setup

1. **Install VS Code Extensions**
   - Open VS Code and install the following extensions:
     - Azure Terraform (by Microsoft)
     - Azure Account (by Microsoft)
     - Terraform (by HashiCorp)
     - Remote - SSH (if working on a remote machine)
     - Kubernetes (by Microsoft)

2. **Clone Repository**
   - Open VS Code
   - Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS)
   - Type "Git: Clone" and select it
   - Enter your repository URL or choose "Clone from GitHub"
   - Select a local folder to store the project

3. **Open Terminal in VS Code**
   - Press `` Ctrl+` `` to open the integrated terminal
   - You'll use this terminal for all commands

4. **Set Up Environment**
   - Run the setup script to install required tools:
     ```bash
     cd aks-fleet-manager
     chmod +x ./scripts/setup-cli.sh
     ./scripts/setup-cli.sh
     ```

## Azure Authentication

1. **Login to Azure**
   - In the VS Code terminal:
     ```bash
     az login
     ```
   - A browser window will open; complete the authentication

2. **Set Subscription**
   - List your subscriptions:
     ```bash
     az account list --output table
     ```
   - Set your subscription:
     ```bash
     az account set --subscription "Your-Subscription-Name-or-ID"
     ```

## Terraform Configuration Verification

Before deploying, verify that your Terraform files are correctly structured:

1. **Check Provider Configuration**
   - Ensure that the provider block is only in `main.tf` and not duplicated in `versions.tf`
   - Your `versions.tf` file should only contain the `terraform` block with `required_providers`
   - If you see a provider block in `versions.tf`, remove it to avoid conflicts

2. **Verify Resource Names**
   - Ensure you're using the correct resource type names:
     - `azurerm_kubernetes_fleet_manager` (not `azurerm_fleet_manager`)
     - `azurerm_kubernetes_fleet_member` (not `azurerm_fleet_member`)
   - Update groups cannot be created directly in Terraform and will be handled post-deployment

3. **Review Kubernetes App Deployment**
   - Examine the `kubernetes_apps.tf` file which deploys demo applications to each cluster
   - Verify the Kubernetes provider configurations are using the correct cluster references
   - Note the different configurations for dev and prod applications

## Terraform Deployment

1. **Initialize Terraform**
   - Navigate to the terraform directory:
     ```bash
     cd terraform
     ```
   - Initialize Terraform:
     ```bash
     terraform init
     ```
   - If you encounter provider errors, verify that you don't have duplicate provider blocks

2. **Review and Edit Variables (Optional)**
   - Open `variables.tf` in VS Code
   - Create a new file `terraform.tfvars` to override any default variables:
     ```hcl
     primary_region   = "eastus"
     secondary_region = "westeurope"
     resource_prefix  = "your-prefix"
     dev_node_count   = 2
     prod_node_count  = 3
     ```

3. **Plan Deployment**
   - Generate an execution plan:
     ```bash
     terraform plan -out=tfplan
     ```
   - Review the plan output in the terminal
   - Verify that the correct resources are being created, including:
     - AKS clusters (2 dev, 2 prod)
     - Fleet Manager
     - VNet peering
     - Front Door configuration
     - Kubernetes deployments and services

4. **Apply Configuration**
   - Deploy the infrastructure:
     ```bash
     terraform apply tfplan
     ```
   - Type `yes` when prompted
   - Monitor the deployment progress (this will take 15-25 minutes for the AKS clusters)
   - The Kubernetes app deployments will happen after the clusters are created

5. **View Outputs**
   - After deployment completes, view outputs:
     ```bash
     terraform output
     ```
   - Note the service IP addresses for the demo applications:
     - dev_eastus_service_ip
     - dev_westeu_service_ip 
     - prod_eastus_service_ip
     - prod_westeu_service_ip

## Post-Deployment Configuration

1. **Create Update Groups with Azure CLI**
   - Make the script executable:
     ```bash
     cd ..
     chmod +x ./scripts/create-update-groups.sh
     ```
   - Run the script:
     ```bash
     ./scripts/create-update-groups.sh
     ```
   - This script uses Azure CLI commands because update groups aren't directly supported in Terraform

2. **Access AKS Clusters**
   - Get credentials for each cluster:
     ```bash
     # You can copy these commands from the terraform output
     az aks get-credentials --resource-group <EASTUS_RG> --name <EASTUS_DEV_CLUSTER> --overwrite-existing
     ```
   - Test kubectl connection:
     ```bash
     kubectl get nodes
     ```

3. **Verify Demo Applications**
   - Check the deployments in each cluster:
     ```bash
     # For development clusters
     kubectl get deployments --context=<DEV_CLUSTER_CONTEXT>
     kubectl get pods --context=<DEV_CLUSTER_CONTEXT>
     kubectl get services --context=<DEV_CLUSTER_CONTEXT>

     # For production clusters
     kubectl get deployments --context=<PROD_CLUSTER_CONTEXT>
     kubectl get pods --context=<PROD_CLUSTER_CONTEXT>
     kubectl get services --context=<PROD_CLUSTER_CONTEXT>
     ```
   - You should see:
     - Development clusters: "dev-demo-app" deployment with 2 replicas
     - Production clusters: "prod-demo-app" deployment with 3 replicas

## Accessing Demo Applications

1. **Direct Access via Service IPs**
   - You can access the applications directly using the service IPs from Terraform outputs:
     ```bash
     # Get service IPs
     terraform output dev_eastus_service_ip
     terraform output prod_eastus_service_ip
     ```
   - Open a browser and navigate to http://<SERVICE_IP>

2. **Access via Front Door**
   - The Front Door configuration routes traffic based on path patterns:
     - Development apps: `https://<FRONT_DOOR_ENDPOINT>/dev/*`
     - Production apps: `https://<FRONT_DOOR_ENDPOINT>/prod/*`
   - Open a browser and navigate to the Front Door endpoint:
     ```bash
     echo "Front Door Endpoint: https://$(terraform output -raw afd_endpoint_hostname)"
     ```

3. **Testing Different Environments**
   - Development apps (Cats vs Dogs voting):
     - Navigate to `https://<FRONT_DOOR_ENDPOINT>/dev/`
   - Production apps (Tea vs Coffee voting):
     - Navigate to `https://<FRONT_DOOR_ENDPOINT>/prod/`

4. **Manual Step in Azure FrontDoor**
   - Get the terraform output for all four AKS clusters service endpoint IP addresses. You can get it from step 3 using kubectl get svc for all four clusters.
   - There is a bug, which does not allow to update the service IP addresses for each AKS cluster in Azure Frontdoor->Origin Groups
   - Manually update the IP addresses for Dev and Prod AKS cluster service IP addresses. Go to Azure portal->Azure Front door->Settings->Origin Groups->dev-origin-group
   - Manually update the IP addresses for Dev and Prod AKS cluster service IP addresses. Go to Azure portal->Azure Front door->Settings->Origin Groups->prod-origin-group       

## Validate Fleet Manager

1. **Check Fleet Manager**
   - In VS Code, install the "Azure Resources" extension
   - Sign in to Azure (if prompted)
   - Navigate to your resource groups in the Azure view
   - Find and click on your Fleet Manager resource
   - Verify the 4 clusters are connected as members

2. **Check AKS Clusters**
   - In VS Code's Kubernetes extension:
     - Ensure you see all 4 clusters in the dropdown
     - Switch between clusters to check nodes
     - Run `kubectl get nodes` for each cluster

3. **Validate Update Groups**
   - In the Azure Portal, navigate to your Fleet Manager
   - Check that both update groups exist with correct clusters

## Common Issues and Solutions

1. **Duplicate Provider Error**
   - **Issue**: Error about duplicate provider configuration
   - **Solution**: Ensure the `provider "azurerm"` block only exists in `main.tf` and is removed from `versions.tf`

2. **Invalid Resource Type Error**
   - **Issue**: Error about invalid resource types like `azurerm_fleet_manager`
   - **Solution**: Use the correct resource type names like `azurerm_kubernetes_fleet_manager`

3. **Missing Resources in Outputs**
   - **Issue**: Errors about references to undeclared resources
   - **Solution**: Ensure all resources referenced in `outputs.tf` are properly defined in `main.tf`

4. **Update Group Creation Failures**
   - **Issue**: Azure CLI fails to create update groups
   - **Solution**: 
     - Verify the Fleet Manager and members are properly created
     - Check member names match exactly as defined in Fleet Manager
     - Ensure the Azure CLI fleet extension is installed

5. **Kubernetes Provider Authentication Issues**
   - **Issue**: Unable to authenticate to Kubernetes clusters
   - **Solution**:
     - Verify AKS clusters were created successfully
     - Check the Kubernetes provider configuration
     - Get fresh kubeconfig credentials with `az aks get-credentials`

6. **Demo Apps Not Accessible via Front Door**
   - **Issue**: Unable to access apps through Front Door
   - **Solution**:
     - Verify service IPs are correct in Front Door origins
     - Check Front Door rules and routing settings
     - Confirm the service is running with `kubectl get services`

## Cleanup (When Needed)

To remove all resources:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted.

## Next Steps

After successful deployment:

1. Test multi-cluster updates using Fleet Manager
2. Modify the demo applications and redeploy
3. Configure monitoring and logging
4. Test an update run across clusters

---

This guide should help you deploy and validate your AKS Fleet Manager setup completely within VS Code's environment.
