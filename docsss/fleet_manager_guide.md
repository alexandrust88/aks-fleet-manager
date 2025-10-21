# Azure Fleet Manager Node Update Onboarding Guide
## 300+ Clusters Across Multiple Subscriptions

---

## Executive Overview

This guide addresses the challenge of managing 300 clusters (dev, stage, prod) across multiple subscriptions using Azure Fleet Manager for **node image updates only**. Key constraint: Fleet Manager currently supports **up to 100 clusters per Fleet per region/tenant**, so you'll need multiple Fleet instances.

**Timeline Estimate:** 6-8 weeks for full production deployment (discovery → pilot → rollout)

---

## 1. Architecture & Planning

### 1.1 Multi-Fleet Strategy (Required for 300+ Clusters)

Since Azure Fleet Manager supports max 100 clusters per Fleet instance, design multiple Fleets:

```
Fleet Structure for 300 Clusters:
├── Fleet-1: Regions [WestEurope, NorthEurope] (100 clusters)
├── Fleet-2: Regions [EastUS, WestUS] (100 clusters)
└── Fleet-3: Regions [Southeast Asia, East Asia] (100 clusters)

Alternative: Group by Environment
├── Fleet-Dev: All dev clusters (100 max)
├── Fleet-Stage: All stage clusters (100 max)
└── Fleet-Prod: All prod clusters (100 max)
```

**Recommendation:** Use **region-based Fleets** for better fault isolation and region-specific update scheduling.

### 1.2 Cluster Classification

Before onboarding, categorize your 300 clusters:

| Attribute | Values | Purpose |
|-----------|--------|---------|
| **Environment** | dev, stage, prod | Update rings |
| **Region** | eastus, westeurope, etc. | Fleet assignment |
| **Age/Type** | old, modern, legacy | Update compatibility |
| **Subscription** | subscription-id | Governance boundary |
| **Tier** | critical, standard, batch | Priority for updates |

Create an **inventory CSV** (see section 4.2).

### 1.3 Limitations & Considerations

- **Max 100 clusters per Fleet** in same Azure AD tenant/region
- **Maintenance windows honored** – updates only during configured windows
- **Consistent vs Latest images** – choose based on multi-region strategy
- **Node image updates only** – control plane remains unmanaged by Fleet for this use case
- **No auto-skip on pending state** – must manually review/skip blocked clusters

---

## 2. Prerequisites & Setup

### 2.1 Prerequisites Checklist

```bash
# 1. Azure CLI (v2.58.0+) with Fleet extension
az --version  # Should be 2.58.0 or later
az extension add --name fleet
az extension update --name fleet

# 2. Required RBAC roles (per subscription)
# - Owner or Contributor on target subscriptions
# - Fleet Administrator on Fleet resources
# - AKS Cluster Admin on member clusters

# 3. Verify tenant access across all subscriptions
az account list -o table  # All subscriptions must share same Azure AD tenant

# 4. Service Principal (for automation)
az ad sp create-for-rbac \
  --role "Contributor" \
  --scopes "/subscriptions/{sub-id}" \
  --name "fleet-automation-sp"
```

### 2.2 Environment Setup

```bash
# Set core variables
export TENANT_ID="your-azure-ad-tenant-id"
export FLEET_NAMING_PREFIX="fleet"  # fleet-eu, fleet-us, etc.
export LOCATION_PRIMARY="westeurope"
export LOCATION_SECONDARY="eastus"

# Subscription mapping
declare -A SUBSCRIPTIONS=(
  ["prod"]="prod-subscription-id"
  ["stage"]="stage-subscription-id"
  ["dev"]="dev-subscription-id"
)
```

---

## 3. Deployment: Step-by-Step

### 3.1 Create Fleet Instances (No Hub Cluster)

Since you only need node updates, create Fleet **without hub cluster** to reduce management overhead.

```bash
#!/bin/bash
# create-fleets.sh

set -e

RESOURCE_GROUP="rg-fleet-management"
LOCATION="westeurope"

# Step 1: Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Step 2: Create three Fleets (regional)
for region in eu us asia; do
  FLEET_NAME="fleet-${region}"
  
  az fleet create \
    --resource-group $RESOURCE_GROUP \
    --name $FLEET_NAME \
    --location $LOCATION \
    --tags environment=prod, purpose=node-updates
  
  echo "✓ Created Fleet: $FLEET_NAME"
done

# Verify Fleets
az fleet list \
  --resource-group $RESOURCE_GROUP \
  -o table
```

### 3.2 Label Clusters for Targeting

Before joining clusters, label them for update strategies.

```bash
#!/bin/bash
# label-clusters.sh

# For each AKS cluster, add Fleet-compatible labels
for cluster_name in $(az aks list --query "[].name" -o tsv); do
  CLUSTER_RG=$(az aks list --query "[?name=='$cluster_name'].resourceGroup" -o tsv)
  
  # Extract metadata from naming convention or tags
  # Example: cluster name = "aks-prod-eu-001"
  ENV=$(echo $cluster_name | cut -d- -f2)  # prod
  REGION=$(echo $cluster_name | cut -d- -f3)  # eu
  
  # Add labels to cluster
  CLUSTER_ID=$(az aks show \
    --resource-group $CLUSTER_RG \
    --name $cluster_name \
    --query id -o tsv)
  
  # Labels are added via Fleet member creation (next step)
  echo "Marked $cluster_name: env=$ENV, region=$REGION"
done
```

### 3.3 Join Clusters to Fleet (Batch Onboarding)

```bash
#!/bin/bash
# join-clusters-to-fleet.sh

set -e

RESOURCE_GROUP="rg-fleet-management"
FLEET_NAME="fleet-eu"  # Change per region

# Read clusters from CSV
while IFS=, read -r cluster_name cluster_rg subscription_id environment region tier; do
  # Skip header
  [[ $cluster_name == "cluster_name" ]] && continue
  
  # Switch to cluster's subscription
  az account set --subscription "$subscription_id"
  
  # Get cluster resource ID
  CLUSTER_ID=$(az aks show \
    --resource-group "$cluster_rg" \
    --name "$cluster_name" \
    --query id -o tsv)
  
  # Define update group based on environment
  UPDATE_GROUP="${environment}-${region}-group"
  
  # Join to Fleet with labels
  az fleet member create \
    --resource-group $RESOURCE_GROUP \
    --fleet-name $FLEET_NAME \
    --name "${cluster_name}" \
    --member-cluster-id "$CLUSTER_ID" \
    --labels "env=${environment}" "region=${region}" "tier=${tier}" \
    --group $UPDATE_GROUP
  
  echo "✓ Joined $cluster_name to $FLEET_NAME (group: $UPDATE_GROUP)"
  
done < clusters-inventory.csv

# Verify all members
az fleet member list \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  -o table
```

### 3.4 Configure Maintenance Windows (per cluster)

Fleet respects cluster maintenance windows. Set them before creating update runs.

```bash
#!/bin/bash
# configure-maintenance-windows.sh

set -e

# Read cluster list
while IFS=, read -r cluster_name cluster_rg subscription_id environment region tier; do
  [[ $cluster_name == "cluster_name" ]] && continue
  
  az account set --subscription "$subscription_id"
  
  # Dev clusters: Tuesday 2-4 AM UTC
  if [[ $environment == "dev" ]]; then
    az aks maintenanceconfiguration add \
      --resource-group "$cluster_rg" \
      --cluster-name "$cluster_name" \
      --name "node-patch-tuesday" \
      --schedule-type Weekly \
      --day Tuesday \
      --start-hour 2 \
      --duration 2
  fi
  
  # Stage clusters: Wednesday 3-5 AM UTC
  if [[ $environment == "stage" ]]; then
    az aks maintenanceconfiguration add \
      --resource-group "$cluster_rg" \
      --cluster-name "$cluster_name" \
      --name "node-patch-wednesday" \
      --schedule-type Weekly \
      --day Wednesday \
      --start-hour 3 \
      --duration 2
  fi
  
  # Prod clusters: Saturday 4-6 AM UTC (low traffic)
  if [[ $environment == "prod" ]]; then
    az aks maintenanceconfiguration add \
      --resource-group "$cluster_rg" \
      --cluster-name "$cluster_name" \
      --name "node-patch-saturday" \
      --schedule-type Weekly \
      --day Saturday \
      --start-hour 4 \
      --duration 2
  fi
  
  echo "✓ Configured maintenance window: $cluster_name ($environment)"
  
done < clusters-inventory.csv
```

### 3.5 Create Update Strategies (Reusable Templates)

Update strategies define the sequence for all future update runs.

```bash
#!/bin/bash
# create-update-strategies.sh

set -e

RESOURCE_GROUP="rg-fleet-management"
FLEET_NAME="fleet-eu"

# Strategy 1: Ring-based (dev → stage → prod)
az fleet updatestrategy create \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "strategy-rings-dev-stage-prod" \
  --stages '[
    {
      "name": "stage-1-dev",
      "groups": [{
        "name": "dev-group",
        "sortOrder": 0
      }],
      "waitDurationSeconds": 300
    },
    {
      "name": "stage-2-stage",
      "groups": [{
        "name": "stage-group",
        "sortOrder": 0
      }],
      "waitDurationSeconds": 600
    },
    {
      "name": "stage-3-prod",
      "groups": [{
        "name": "prod-group",
        "sortOrder": 0
      }],
      "waitDurationSeconds": 0
    }
  ]'

# Strategy 2: Canary (1 cluster at a time from prod)
az fleet updatestrategy create \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "strategy-canary-prod" \
  --stages '[
    {
      "name": "canary-wave-1",
      "groups": [{
        "name": "prod-canary-001",
        "sortOrder": 0
      }],
      "waitDurationSeconds": 900
    },
    {
      "name": "canary-wave-2",
      "groups": [{
        "name": "prod-wave-2",
        "sortOrder": 0
      }],
      "waitDurationSeconds": 0
    }
  ]'

echo "✓ Created update strategies"
```

### 3.6 Create Auto-Upgrade Profile (Optional but Recommended)

Auto-upgrade profiles automatically create update runs when new node images are released.

```bash
#!/bin/bash
# create-auto-upgrade-profile.sh

set -e

RESOURCE_GROUP="rg-fleet-management"
FLEET_NAME="fleet-eu"
STRATEGY_ID="/subscriptions/{sub}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerService/fleets/${FLEET_NAME}/updateStrategies/strategy-rings-dev-stage-prod"

# Create auto-upgrade profile for NodeImage channel
az fleet autoupgradeprofile create \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "nodeimage-auto-upgrade" \
  --channel NodeImage \
  --update-strategy-id "$STRATEGY_ID"

echo "✓ Auto-upgrade profile created"
echo "⚠ Note: Auto-upgrade profiles generate runs but don't auto-start them"
echo "  You must manually review and start each run"
```

---

## 4. Operations & Monitoring

### 4.1 Create and Execute Update Runs

```bash
#!/bin/bash
# execute-update-run.sh

set -e

RESOURCE_GROUP="rg-fleet-management"
FLEET_NAME="fleet-eu"
STRATEGY_ID="/subscriptions/{sub}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerService/fleets/${FLEET_NAME}/updateStrategies/strategy-rings-dev-stage-prod"

# Create update run using strategy
RUN_NAME="nodeimage-run-$(date +%Y%m%d-%H%M%S)"

az fleet updateruns create \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "$RUN_NAME" \
  --update-strategy-id "$STRATEGY_ID" \
  --upgrade-type NodeImage \
  --node-image-selection Consistent

echo "✓ Created update run: $RUN_NAME"
echo "  Status: Not Started (ready for manual review)"

# Review run details
az fleet updateruns show \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "$RUN_NAME" \
  -o jsonc

# Approve and start
read -p "Start this update run? (yes/no): " confirm
if [[ $confirm == "yes" ]]; then
  az fleet updateruns start \
    --resource-group $RESOURCE_GROUP \
    --fleet-name $FLEET_NAME \
    --name "$RUN_NAME"
  echo "✓ Update run started"
fi
```

### 4.2 Monitor Update Run Progress

```bash
#!/bin/bash
# monitor-update-run.sh

RESOURCE_GROUP="rg-fleet-management"
FLEET_NAME="fleet-eu"
RUN_NAME="$1"

if [[ -z $RUN_NAME ]]; then
  echo "Usage: $0 <run-name>"
  exit 1
fi

echo "Monitoring update run: $RUN_NAME"
echo "=================================="

while true; do
  STATUS=$(az fleet updateruns show \
    --resource-group $RESOURCE_GROUP \
    --fleet-name $FLEET_NAME \
    --name "$RUN_NAME" \
    --query 'status' -o tsv)
  
  echo "Status: $STATUS"
  
  # Show member progress
  az fleet updateruns members list \
    --resource-group $RESOURCE_GROUP \
    --fleet-name $FLEET_NAME \
    --update-run-name "$RUN_NAME" \
    --query "[].{Cluster:name, Status:status, Reason:reason}" \
    -o table
  
  [[ "$STATUS" != "Running" ]] && break
  
  sleep 30
done

echo "✓ Update run completed"
```

### 4.3 Handle Blocked Clusters

Clusters may get stuck due to maintenance windows or missing image in region.

```bash
#!/bin/bash
# manage-blocked-clusters.sh

RESOURCE_GROUP="rg-fleet-management"
FLEET_NAME="fleet-eu"
RUN_NAME="$1"
CLUSTER_NAME="$2"

# Check why cluster is pending
az fleet updateruns members show \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --update-run-name "$RUN_NAME" \
  --name "$CLUSTER_NAME" \
  -o jsonc

# Option 1: Skip cluster (only if necessary)
az fleet updateruns skip \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --update-run-name "$RUN_NAME" \
  --member-name "$CLUSTER_NAME"

echo "⚠ Cluster $CLUSTER_NAME skipped from update run"
```

---

## 5. Inventory Management

### 5.1 Cluster Inventory CSV Template

```csv
cluster_name,cluster_rg,subscription_id,environment,region,tier,kubernetes_version,node_os_image,last_updated
aks-dev-eu-001,rg-dev-eu,sub-dev,dev,westeurope,standard,1.30.0,Ubuntu,2024-01-15
aks-dev-eu-002,rg-dev-eu,sub-dev,dev,westeurope,standard,1.29.5,Ubuntu,2023-12-20
aks-stage-eu-001,rg-stage-eu,sub-stage,stage,westeurope,critical,1.30.0,Ubuntu,2024-01-10
aks-prod-eu-001,rg-prod-eu,sub-prod,prod,westeurope,critical,1.29.5,AzureLinux,2023-11-30
aks-prod-us-001,rg-prod-us,sub-prod,prod,eastus,critical,1.29.5,AzureLinux,2023-11-28
```

### 5.2 Discovery Script

```bash
#!/bin/bash
# discover-clusters.sh

echo "cluster_name,cluster_rg,subscription_id,environment,region,tier,kubernetes_version,node_os_image" > clusters-inventory.csv

for sub in $(az account list --query "[].id" -o tsv); do
  az account set --subscription $sub
  
  az aks list --query "[].{
    name:name,
    resourceGroup:resourceGroup,
    subscription:'$sub',
    kubernetesVersion:kubernetesVersion
  }" -o tsv | while read cluster_name rg sub k8s_ver; do
    
    # Extract environment and region from tags or naming
    ENV=$(az aks show -g $rg -n $cluster_name --query "tags.environment" -o tsv)
    REGION=$(az aks show -g $rg -n $cluster_name --query "location" -o tsv)
    TIER=$(az aks show -g $rg -n $cluster_name --query "tags.tier" -o tsv)
    
    echo "$cluster_name,$rg,$sub,$ENV,$REGION,$TIER,$k8s_ver" >> clusters-inventory.csv
  done
done

echo "✓ Discovered all clusters in clusters-inventory.csv"
```

---

## 6. Best Practices for 300+ Clusters

### 6.1 Deployment Phases

| Phase | Duration | Scope | Risk |
|-------|----------|-------|------|
| **Phase 0: Pilot** | 1-2 weeks | 5-10 dev/stage clusters | Low |
| **Phase 1: Dev Fleet** | 2-3 weeks | All dev clusters (~100) | Low |
| **Phase 2: Stage Fleet** | 2-3 weeks | All stage clusters (~100) | Medium |
| **Phase 3: Prod Fleets** | 3-4 weeks | All prod clusters (~100) | High |

### 6.2 Monitoring & Alerting

```bash
# Set up alerts for failed update runs
az monitor metrics alert create \
  --name "fleet-update-failures" \
  --resource-group $RESOURCE_GROUP \
  --scopes "/subscriptions/{sub}/resourceGroups/${RESOURCE_GROUP}" \
  --condition "avg UpdateRunFailureRate > 0" \
  --action email --email-receiver admin@company.com
```

### 6.3 Documentation Requirements

For each Fleet, document:
- Fleet name, region(s), member count
- Update strategies and their purpose
- Maintenance windows per environment
- On-call escalation for stuck clusters
- Rollback procedures per cluster type
- Historical update run logs

### 6.4 Handling Diverse Cluster Types

For old/legacy clusters with compatibility issues:

```bash
# Option 1: Separate update strategy for old clusters
az fleet updatestrategy create \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "strategy-legacy-clusters" \
  --stages '[...]'  # Conservative, slower rollout

# Option 2: Disable auto-upgrade for specific clusters
az fleet member update \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "aks-legacy-001" \
  --labels "exclude-auto-upgrade=true"
```

---

## 7. Troubleshooting Common Issues

### Issue: Cluster Stuck in "Pending" State

**Cause:** Maintenance window closed or image not available in region.

**Solution:**
```bash
# Check cluster maintenance window
az aks maintenanceconfiguration list \
  --resource-group $CLUSTER_RG \
  --cluster-name $CLUSTER_NAME

# Check if image available in region
az aks get-versions --location $REGION

# If necessary, skip cluster
az fleet updateruns skip \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --update-run-name $RUN_NAME \
  --member-name $CLUSTER_NAME
```

### Issue: Update Run Timed Out

**Cause:** Clusters exceed 90-minute timeout window.

**Solution:**
- Reduce clusters per update run
- Increase timeout in subscription settings
- Use more granular update groups

### Issue: Inconsistent Node Image Across Regions

**Cause:** Using "Latest image" instead of "Consistent image".

**Solution:**
```bash
# Always use Consistent image for multi-region fleets
az fleet updateruns create \
  --resource-group $RESOURCE_GROUP \
  --fleet-name $FLEET_NAME \
  --name "$RUN_NAME" \
  --upgrade-type NodeImage \
  --node-image-selection Consistent  # ← Use this
```

---

## 8. Checklist for Production Deployment

- [ ] All 300 clusters discovered and labeled
- [ ] Maintenance windows configured per environment
- [ ] Three regional Fleets created
- [ ] Update strategies defined (rings, canary, etc.)
- [ ] Pilot phase completed (5-10 clusters)
- [ ] Dev environment fully onboarded
- [ ] Stage environment fully onboarded
- [ ] Prod environment fully onboarded (staged rollout)
- [ ] Auto-upgrade profiles tested
- [ ] Runbooks for ops team documented
- [ ] Alerting configured for failed runs
- [ ] Rollback procedures tested
- [ ] Cost impact validated

---

## 9. Key References

- Official Docs: https://learn.microsoft.com/azure/kubernetes-fleet/
- Update Orchestration: https://learn.microsoft.com/azure/kubernetes-fleet/concepts-update-orchestration
- Auto-Upgrade: https://learn.microsoft.com/azure/kubernetes-fleet/update-automation
- FAQ: https://learn.microsoft.com/azure/kubernetes-fleet/faq

---

## 10. Support & Escalation

**Issue Type** → **Owner** → **Resolution Path**
- Fleet creation failures → Azure Support → Service limits/quotas
- Cluster connectivity issues → Network team → NSG/firewall rules
- Update compatibility issues → App team → Version compatibility testing
- Performance degradation → Platform team → Cluster scaling

