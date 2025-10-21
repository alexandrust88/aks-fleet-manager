# AKS Fleet Manager – Full Command & YAML Reference (hub3 / westus2)

## 🧭 Environment Overview

| Resource Type | Name                     | Location | Resource Group       | Notes |
|----------------|--------------------------|-----------|----------------------|--------|
| **Fleet Hub**  | hub3                     | westus2   | NetworkWatcherRG     | Active, `Succeeded` |
| **Member #1**  | member1-networkwatcherrg | westus2   | NetworkWatcherRG     | 2 nodes, joined |
| **Member #2**  | m2-networkwatcherrg      | westus2   | NetworkWatcherRG     | 1 node, joined |

---

## 🔹 Fleet Management Commands

```bash
# List all Fleet resources in the subscription
az fleet list -o table

# Show Fleet hub details
az fleet show -g NetworkWatcherRG -n hub3 -o jsonc

# List Fleet members
az fleet member list -g NetworkWatcherRG -f hub3 -o table
```

---

## 🔹 Export Hub Kubeconfig

```bash
# Export Fleet Hub kubeconfig to a new file
az fleet get-credentials \
  --resource-group NetworkWatcherRG \
  --name hub3 \
  --file ~/hub3-fleet-kubeconfig.yaml

# Convert AAD credentials to kubelogin format
kubelogin convert-kubeconfig -l azurecli

# Verify connection
kubectl --kubeconfig ~/hub3-fleet-kubeconfig.yaml get nodes
```

---

## 🔹 Verify Fleet CRDs and Member Clusters

```bash
# List Fleet-related CRDs
kubectl get crd | grep fleet

# List joined member clusters
kubectl get memberclusters

# Show resource usage and labels
kubectl get memberclusters --show-labels

# Describe individual member clusters
kubectl describe membercluster member1-networkwatcherrg
kubectl describe membercluster m2-networkwatcherrg
```

---

## 🔹 Create Namespace and Apply Placement

```bash
# Create namespace for app workloads
kubectl create ns apps

# Apply placement definition (propagate namespace)
kubectl apply -f clusterresourceplacement.yaml

# Verify placements
kubectl get clusterresourceplacements
kubectl describe clusterresourceplacement appscrp
```

---

## 🔹 Label Member Clusters for Placement Affinity

```bash
# Label clusters for workload placement logic
kubectl label membercluster member1-networkwatcherrg env=prod
kubectl label membercluster m2-networkwatcherrg env=dev

# Confirm labels
kubectl get memberclusters --show-labels
```

---

## 🔹 Example YAML: MemberCluster Resource

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: MemberCluster
metadata:
  name: member1-networkwatcherrg
  labels:
    fleet.azure.com/location: westus2
    fleet.azure.com/resource-group: NetworkWatcherRG
    fleet.azure.com/subscription-id: <YOUR_SUBSCRIPTION_ID>
    env: prod
spec:
  heartbeatPeriodSeconds: 15
  identity:
    kind: User
    name: CLUSTER_SAMI_GUID
```

---

## 🔹 Example YAML: ClusterResourcePlacement (All Members)

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: ClusterResourcePlacement
metadata:
  name: appscrp
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      name: apps
  policy:
    placementType: PickAll
```

---

## 🔹 Example YAML: ClusterResourcePlacement (Env=Prod)

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: ClusterResourcePlacement
metadata:
  name: appscrp-prod
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      name: apps
  policy:
    placementType: PickAll
    affinity:
      clusterAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          clusterSelectorTerms:
            - matchExpressions:
                - key: env
                  operator: In
                  values:
                    - prod
```

---

## 🔹 Example YAML: ClusterResourcePlacement (Fixed Cluster List)

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: ClusterResourcePlacement
metadata:
  name: appscrp-fixed
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      name: apps
  policy:
    placementType: PickFixed
    clusterNames:
      - member1-networkwatcherrg
```

---

## 🔹 Example YAML: Placement Based on Node Count

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: ClusterResourcePlacement
metadata:
  name: appscrp-most-nodes
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      name: apps
  policy:
    placementType: PickN
    numberOfClusters: 1
    orderBy:
      - key: kubernetes-fleet.io/node-count
        order: Descending
```

---

## 🔹 Example YAML: MemberCluster Status (Metrics Snapshot)

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: MemberCluster
metadata:
  name: m2-networkwatcherrg
spec:
  heartbeatPeriodSeconds: 15
  identity:
    kind: User
    name: CLUSTER_SAMI_GUID
status:
  properties:
    kubernetes-fleet.io/node-count:
      observationTime: "2025-10-21T12:00:00Z"
      value: "1"
    kubernetes.azure.com/per-cpu-core-cost:
      observationTime: "2025-10-21T12:00:00Z"
      value: "0.057"
    kubernetes.azure.com/per-gb-memory-cost:
      observationTime: "2025-10-21T12:00:00Z"
      value: "0.017"
  resourceUsage:
    allocatable:
      cpu: 950m
      memory: 2700Mi
    available:
      cpu: 478m
      memory: 1900Mi
    capacity:
      cpu: "1"
      memory: 3000Mi
```

---

## 🔹 Validate Resource Propagation

```bash
# Confirm namespace 'apps' exists across all clusters
kubectl get ns apps --context hub3
kubectl get ns apps --context member1-networkwatcherrg
kubectl get ns apps --context m2-networkwatcherrg

# Check that workloads are scheduled correctly
kubectl get deploy,svc -n apps
```

---

## 🔹 Delete and Cleanup

```bash
# Remove workload and placements
kubectl delete -f clusterresourceplacement.yaml
kubectl delete ns apps

# Detach a member cluster (if needed)
az fleet member delete -g NetworkWatcherRG -f hub3 -n member1-networkwatcherrg -y
```

---

## 🔹 Quick Diagnostic Commands

```bash
# Check Fleet agents running in the hub cluster
kubectl get pods -n kube-system | grep fleet

# Show Fleet API resources
kubectl api-resources | grep fleet

# Check last heartbeat for all members
kubectl get memberclusters -o custom-columns=NAME:.metadata.name,LASTSEEN:.status.conditions[0].lastTransitionTime
```

---

## ✅ References

- https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-fleet  
- https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-resource-propagation  
- https://learn.microsoft.com/en-us/azure/kubernetes-fleet/intelligent-resource-placement  
- https://github.com/Azure/fleet  
- https://github.com/Azure/fleet-networking
