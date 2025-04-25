#!/bin/bash
set -e

echo "Setting up CLI tools for AKS Fleet Manager deployment..."

# Check/install Azure CLI
if ! command -v az &> /dev/null; then
    echo "Azure CLI not found. Installing..."
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew update && brew install azure-cli
    else
        echo "Unsupported OS. Please install Azure CLI manually: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
else
    echo "Azure CLI already installed."
    az version
fi

# Check/install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Terraform not found. Installing..."
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
        sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
        sudo apt-get update && sudo apt-get install terraform
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
    else
        echo "Unsupported OS. Please install Terraform manually: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        exit 1
    fi
else
    echo "Terraform already installed."
    terraform version
fi

# Check/install kubectl
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Installing..."
    az aks install-cli
else
    echo "kubectl already installed."
    kubectl version --client
fi

# Check/install Fleet extension for Azure CLI
if ! az extension show --name fleet &> /dev/null; then
    echo "Installing Azure CLI fleet extension..."
    az extension add --name fleet
else
    echo "Azure CLI fleet extension already installed."
    az extension show --name fleet
fi

echo "Checking Azure login status..."
if ! az account show &> /dev/null; then
    echo "Please log in to Azure:"
    az login
else
    echo "Already logged in to Azure."
    az account show -o table
fi

echo "CLI setup complete! You're ready to deploy the AKS Fleet Manager."