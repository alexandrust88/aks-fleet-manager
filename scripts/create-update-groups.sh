#!/bin/bash
set -e

# Check if the fleet extension is installed
if ! az extension show --name fleet &> /dev/null; then
    echo "Installing Azure CLI fleet extension..."
    az extension add --name fleet
fi

# Dynamically get the first available Fleet Manager
echo "Finding existing Fleet Manager..."
FLEET_NAME=$(az fleet list --query "[0].name" -o tsv 2>/dev/null)
FLEET_MANAGER_RG=$(az fleet list --query "[0].resourceGroup" -o tsv 2>/dev/null)

if [ -z "$FLEET_NAME" ] || [ -z "$FLEET_MANAGER_RG" ]; then
    echo "Error: No Fleet Manager found in the current subscription."
    echo "Please make sure you are logged into the correct subscription with: az account set --subscription <subscription-id>"
    exit 1
fi

echo "Found Fleet Manager:"
echo "Resource Group: $FLEET_MANAGER_RG"
echo "Fleet Name: $FLEET_NAME"

# List the member clusters to confirm connectivity
echo "Listing member clusters:"
az fleet member list --resource-group "$FLEET_MANAGER_RG" --fleet-name "$FLEET_NAME" -o table

# Create dev_stages.json file
echo "Creating dev_stages.json file..."
cat > dev_stages.json << EOL
{
  "stages": [
    {
      "name": "dev-stage-1",
      "groups": [
        { "name": "development" }
      ],
      "afterStageWaitInSeconds": 600
    }
  ]
}
EOL

# Create prod_stages.json file 
echo "Creating prod_stages.json file..."
cat > prod_stages.json << EOL
{
  "stages": [
    {
      "name": "prod-stage-1",
      "groups": [
        { "name": "production" }
      ],
      "afterStageWaitInSeconds": 1800
    }
  ]
}
EOL

# Try the updatestrategy command with file path
echo "Creating development update strategy..."
az fleet updatestrategy create \
  --resource-group "$FLEET_MANAGER_RG" \
  --fleet-name "$FLEET_NAME" \
  --name "development-strategy" \
  --stages "dev_stages.json"

echo "Creating production update strategy..."
az fleet updatestrategy create \
  --resource-group "$FLEET_MANAGER_RG" \
  --fleet-name "$FLEET_NAME" \
  --name "production-strategy" \
  --stages "prod_stages.json"

echo "Update strategies created successfully!"
echo "You can now use these strategies to orchestrate updates across your AKS clusters."