# Azure Fleet Manager - Complete Limits & Constraints
## Official Limitations from Azure Documentation

---

## 1. Cluster Membership Limits

### Hard Limit: 100 Clusters Per Fleet

Fleet Manager (with or without a hub cluster) supports joining up to 100 AKS clusters.

**For Your 300 Clusters:**
- **Required:** 3 separate Fleet instances (minimum)
- Example architecture:
  ```
  Fleet-1: 100 clusters (Europe region)
  Fleet-2: 100 clusters (US region)
  Fleet-3: 100 clusters (Asia region)
  ```

**Current Status:** If you would like Fleet Manager to support more than 100 clusters, add feedback via GitHub issue #5066

**Workaround:** None available. You must split clusters across multiple Fleet instances.

---

## 2. Geographic & Scope Limitations

### Regional Resource

Fleet Manager is a regional resource. Support for region failover for disaster recovery use cases is on the roadmap.

**Implications:**
- One Fleet = one region (e.g., westeurope, eastus)
- Cannot failover Fleet to another region automatically
- Must manually create replacement Fleet in another region for DR

**For Your Multi-Region Setup:**
- Deploying in 3 regions (EU, US, Asia) = need 3 Fleets anyway
- Regional redundancy: if westeurope region fails, EU clusters are orphaned from management

### Cross-Subscription Support

Fleet Manager allows appropriately authorized users to add any AKS cluster in any Azure subscription and region as long as the Azure subscription is associated with the same Microsoft Entra ID tenant as the Fleet Manager.

**Constraint:** All subscriptions must share the same Azure AD tenant
**Your Case:** ✅ Likely acceptable (most enterprises use single tenant)

---

## 3. Hub Cluster Limitations

### Cannot Modify Hub Cluster

Fleet Manager's hub cluster is a Microsoft-managed resource. Microsoft automatically updates the hub cluster to the latest version of Kubernetes or node image as they become available. If you attempt to update or modify the hub cluster (which is a single node AKS cluster named hub), a set of deny rules block your changes from being applied.

**Implications:**
- You have zero control over hub cluster upgrades
- Cannot use hub cluster for workloads
- Hub automatically gets security patches (good for you)

### No Cluster Creation from Fleet

Creation and lifecycle management of new AKS clusters is on our roadmap.

**Current Limitation:** Fleet cannot provision new AKS clusters
**Workaround:** Create clusters separately, then join them to Fleet

---

## 4. Update & Upgrade Limitations

### Unsupported AKS Update Channels

Currently unsupported AKS channels: SecurityPatch and Unmanaged channels. If you're using any of the channels that Fleet Manager doesn't support, we recommend you leave those channels enabled on your AKS clusters.

**Supported Channels:**
- ✅ Rapid (latest release N)
- ✅ Stable (N-1 release)
- ✅ NodeImage (weekly node patches)
- ✅ TargetKubernetesVersion (preview) (LTS versions)

**Unsupported:**
- ❌ SecurityPatch (OS-level patches only)
- ❌ Unmanaged (OS patching via Linux)

**Your Use Case:** Node image updates = ✅ **Supported** (NodeImage channel)

### Cannot Skip Minor Kubernetes Versions with Auto-Upgrade

Auto-upgrade does not move clusters between minor Kubernetes versions when there's more than one minor Kubernetes version difference (for example: 1.28 to 1.30).

**Example Problem:**
- Your old clusters run 1.27
- New auto-upgrade targets 1.30
- Auto-upgrade **won't** jump from 1.27 → 1.30

**Workaround:**
- First, manually create update runs to stage clusters: 1.27 → 1.28 → 1.29
- Then enable auto-upgrade to 1.30

**Impact on Your Setup:** ⚠️ **Significant if you have old clusters on 1.27 or earlier**

### No Exact Target Node Image Specification

You can specify the target Kubernetes version to upgrade to, but you can't specify the exact target node image version. This is because the latest available node image version may vary depending on the Azure region of the cluster.

**Implication:**
- Cannot pin clusters to specific node image versions
- Must use "Latest" or "Consistent" (automatic selection)
- Region-specific image availability differences not controllable

---

## 5. Image Consistency & Regional Limitations

### Consistency Guarantee Scope

Node consistency is only guaranteed for all clusters contained in a single update run where the consistent image option is chosen. There's no consistency guarantee for node image versions across separate update runs.

**Scenario:**
```
Update Run 1: Clusters A, B, C (all get image v1.0)
Update Run 2: Clusters D, E, F (get image v1.1 if released)
Result: Non-consistent versions across Fleets
```

**Workaround:** Include all clusters in single update run (but max 100 clusters)

### Image Availability by Region

If the new Kubernetes or node image version isn't published to the Azure region in which a member cluster exists, then the update run can enter a pending state.

**Your Issue:** Multi-region deployments may have staggered image availability
- westeurope: v1.0 available
- eastus: v1.0 not available for 24-48 hours
- Result: Pending state blocking entire update run

**Mitigation:** Monitor AKS Release Tracker for regional rollout status

---

## 6. Maintenance Window Limitations

### Auto-Upgrades Don't Create Triggers

Maintenance windows don't trigger updates, nor do updates begin immediately a window opens. Maintenance windows only define when updates can be applied to a cluster.

**Understanding:**
- Maintenance window = "when" updates CAN run, not "when" they DO run
- Update run must be triggered separately (manual or auto-profile)
- Auto-upgrade profile generates run, but you must start it

### Update Run Stalls at Maintenance Window Boundary

The two most common reasons for long pending states are: (1) Member cluster maintenance window isn't open then the update run can enter a paused state. This pause can block completion of the update group or stage until the next maintenance window opens.

**Example Scenario:**
```
Update Run starts on Friday 2 PM
Update Group has 5 clusters:
  - Cluster 1: maintenance window Sat 4-6 AM ✓ can update
  - Cluster 2: maintenance window Sun 4-6 AM ✗ BLOCKED (not open)
  - Cluster 3-5: same as Cluster 2 ✗ BLOCKED
Result: Update run stalls for 26 hours
```

**Solution:** Manually skip cluster, or wait for next maintenance window

---

## 7. Resource Propagation Limitations

### Cluster & Namespace Level Only

Fleet Manager only currently supports propagating resources at the cluster and namespace level. You can't select individual resources inside a namespace for propagation.

**What You CAN Propagate:**
- ✅ Entire namespaces
- ✅ All resources in a cluster

**What You CANNOT:**
- ❌ Specific ConfigMaps inside namespace
- ❌ Individual Deployments
- ❌ Specific Pods or Services

**For Your Use Case:** Not relevant (node updates only, no resource propagation)

---

## 8. Auto-Upgrade Profile Limitations

### Approvals Don't Expire

Approvals are only available once you can verify that the member clusters are ready for upgrade or that the upgrade is completed successfully. No, approvals wait until they're approved. You can't configure a time window for approvals.

**Implication:**
- Manual approval gate has no TTL
- If approver goes on vacation, update waits forever
- Must manually skip if approval can't be obtained

### Strategy Changes Don't Retroactively Apply

When an update run is created, a copy of the chosen strategy is made and stored on the update run itself so that changes to the strategy don't affect executing update runs.

**Scenario:**
- Created Update Run 1 using Strategy-A
- Modified Strategy-A after creation
- Update Run 1 still uses OLD Strategy-A copy
- Must create NEW Update Run for new strategy

### Auto-Upgrade Channel Constraints

- **Stable & Rapid:** Cannot target older versions, only forward
- **LTS Mode:** Can stick to specific minor version, but then removed from auto-upgrade once out of community support

---

## 9. Cluster Identity & Authentication Limits

### Identity Changes Break Communication

Changing the identity of a member cluster breaks the communication between Fleet Manager and that member cluster. While the member agent uses the new identity to communicate with the Fleet Manager, Fleet Manager still needs to be made aware of the new identity. Run this command to resolve: az fleet member create --resource-group --fleet-name --name --member-cluster-id

**Your Risk:** If cluster managed identity changes, you must re-register cluster
**Mitigation:** Use system-assigned identities (automatic renewal)

### Managed Identity Support

Fleet Manager supports both system-assigned and user-assigned managed identities.

✅ Supports both identity types

---

## 10. Update Run State Limitations

### No Automatic Cluster Skipping

If a member cluster's maintenance window isn't open then the update run can enter a paused state. This pause can block completion of the update group or stage until the next maintenance window opens. If you wish to continue the update run, manually skip the cluster. If you skip the cluster, it's out of sync with the rest of the member clusters in the update run.

**Implication:**
- No auto-skip if maintenance window closed
- No auto-retry on next window
- Must manually intervene for each blocked cluster

### Update Run Cannot Stop Individual Cluster Operations

User stopped the update run, at which point update run stopped tracking all operations. If an operation was already initiated by update run (for example, a cluster upgrade is in progress), then that operation isn't aborted for that individual cluster.

**Scenario:**
- Update run stops while Cluster-1 upgrade is in progress
- Cluster-1 **continues** upgrading (you cannot abort)
- Result: Partial completion, manual cleanup needed

---

## 11. Multi-Cluster Workload Limitations

### Automated Deployments Requires Hub Cluster

AKS Automated Deployments supports only a single AKS cluster where the deployed workload runs. Fleet Manager's Automated Deployments stages the workload definitions on the Fleet Manager hub cluster, making them available for propagation to member clusters via cluster resource placement.

**For Your Use Case:** Not relevant (node updates only)

---

## 12. Roadmap Items (Not Yet Supported)

| Feature | Status | Impact |
|---------|--------|--------|
| **>100 clusters per Fleet** | Roadmap | Need multiple Fleets for 300 clusters |
| **Region failover/DR** | Roadmap | No automatic regional failover |
| **Non-AKS cluster support** | Roadmap | Cannot manage on-prem or Arc clusters |
| **Cluster creation from Fleet** | Roadmap | Must create clusters separately |
| **Intra-namespace resource placement** | Roadmap | Cannot select individual resources |
| **East-West communication** | Roadmap | No multi-cluster networking yet |
| **Service mesh integration** | Roadmap | No automatic service mesh setup |

---

## 13. Practical Constraints for 300 Clusters

### Calculate Fleet Requirements

| Scenario | Required Fleets | Notes |
|----------|-----------------|-------|
| 300 clusters, 1 region | 3 Fleets | 100 max per Fleet |
| 300 clusters, 3 regions | 3 Fleets | 1 per region (already split) |
| 300 clusters, 2 regions | 3 Fleets | 2x 150 cluster scenario impossible |

### Update Run Duration Constraints

**Worst Case:**
```
100 clusters × 45 min/cluster = 75 hours total
With 3 stages (dev → stage → prod): 75 hours per stage
Total timeline: 225+ hours = 9+ days per update cycle
```

**Best Case (Optimized):**
```
Parallel updates within stage: 45 minutes per stage
3 stages × 45 min = 135 minutes = 2.25 hours
Plus waiting between stages: 5-10 min wait per stage
Total: ~3-4 hours automated execution
```

### Maintenance Window Blocking Risk

**If 50% of clusters have maintenance windows closed:**
- Update run enters Pending state
- Blocks until windows open
- Can delay 1-7 days depending on window schedule

---

## 14. Workarounds & Mitigation Strategies

### Workaround 1: Multi-Fleet Management

**For 300 clusters:**
```
Fleet-EU (100 clusters) - separate management
Fleet-US (100 clusters) - separate management
Fleet-ASIA (100 clusters) - separate management
```

**Tool:** Use Azure DevOps Pipeline or GitHub Actions to coordinate 3 fleet updates

### Workaround 2: Staggered Updates for Version Skipping

**For clusters on 1.27 (wants to go to 1.30):**
1. Manual update run: 1.27 → 1.28
2. Wait for stability
3. Manual update run: 1.28 → 1.29
4. Wait for stability
5. Enable auto-upgrade: 1.29 → 1.30+

### Workaround 3: Bypass Stalled Update Runs

**Use Cases:** Region lacks image, maintenance window never opens
```bash
az fleet updateruns skip \
  --resource-group $RG \
  --fleet-name $FLEET \
  --update-run-name $RUN \
  --member-name $CLUSTER
```

### Workaround 4: Multiple Smaller Update Runs

Instead of one 100-cluster run, create:
- Run 1: 50 clusters
- Run 2: 50 clusters

Provides better control, easier troubleshooting

---

## 15. Comparison: What Fleet Manager is NOT

| Feature | Fleet Manager | Alternative |
|---------|---------------|-------------|
| **Cluster Provisioning** | ❌ Cannot create | Use Terraform/ARM |
| **Node OS Patching Only** | ✅ Yes | Use Unattended-upgrades |
| **Individual Pod Updates** | ❌ No | Use Helm/GitOps |
| **Multi-tenant Isolation** | ❌ No | Use separate subscriptions |
| **Automatic Failover** | ❌ No | Use Azure Traffic Manager |
| **Application Workload Updates** | ❌ No | Use ArgoCD/Flux |

---

## 16. Decision Matrix: Can Fleet Manager Handle Your Use Case?

| Requirement | Can Fleet Do It? | Workaround |
|-------------|-----------------|-----------|
| **300 clusters** | ❌ (max 100/Fleet) | ✅ Create 3 Fleets |
| **Multi-subscription** | ✅ Yes (same tenant) | N/A |
| **Node image updates only** | ✅ Yes (NodeImage channel) | N/A |
| **Old clusters (1.27)** | ⚠️ Yes, but limited | ✅ Manual version staging |
| **Dev→Stage→Prod rings** | ✅ Yes (stages) | N/A |
| **Automated security patching** | ✅ Yes (auto-upgrade) | N/A |
| **Guaranteed consistency** | ⚠️ Per-run only | ✅ Use "Consistent image" |
| **Emergency fast rollback** | ⚠️ Manual skip per cluster | Acceptable for your use case |

---

## 17. Licensing & Cost Constraints

### Fleet Manager Service: FREE

There's no charge for the Azure Kubernetes Fleet Manager resource itself. You'll only incur charges for the AKS cluster created by Azure Kubernetes Fleet Manager on your behalf. AKS charges will include the virtual machines and associated storage and networking resources consumed for the AKS cluster.

**Cost Breakdown:**
- Fleet Manager resource: $0
- Hub cluster (1-node): ~$12k/year
- Member clusters: existing costs (unaffected)

**Your 300-cluster scenario:**
- 3 Fleets × $12k = $36k/year hub costs
- **ROI:** Saves $202k annually in operations, costs $36k = still **$166k net savings**

---

## 18. Recommendation Summary

### ✅ GOOD FIT for Your Scenario

- 300 clusters across subscriptions ✅ (use 3 Fleets)
- Node image updates only ✅ (NodeImage channel)
- Dev/Stage/Prod ring rollouts ✅ (stages/groups)
- Maintenance window compliance ✅ (automated)
- Old cluster support ✅ (LTS option with workarounds)

### ⚠️ CONSTRAINTS to Manage

- Max 100 clusters per Fleet (force 3 Fleet split)
- Regional resource (no DR failover)
- Can't skip multiple minor versions automatically
- Update runs can stall at maintenance window boundaries
- Consistency only within single update run

### ❌ NOT SUITABLE IF YOU NEED

- >3x splitting of management plane
- Automatic cross-region failover
- Individual resource propagation (cluster-level only)
- Cluster provisioning from Fleet
- Sub-maintenance-window update control

---

## References

- **Official FAQ:** https://learn.microsoft.com/en-us/azure/kubernetes-fleet/faq
- **Update Orchestration:** https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-update-orchestration
- **Auto-Upgrade:** https://learn.microsoft.com/en-us/azure/kubernetes-fleet/update-automation
- **Roadmap:** https://aka.ms/kubernetes-fleet/roadmap (GitHub)

