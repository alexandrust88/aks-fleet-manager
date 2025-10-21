# AKS Fleet Manager Overview
az fleet list -o table   
az fleet get-credentials --resource-group NetworkWatcherRG --name hub3 --file ~/hub3-fleet-kubeconfig.yaml               
32284  kubectl get nodes
32285  az login
32286  az fleet get-credentials --resource-group NetworkWatcherRG --name hub3 --file ~/hub3-fleet-kubeconfig.yaml
32287  kubelogin convert-kubeconfig -l azurecli
32288  kubectl get nodes
32289  code .
32290  ls
32291  cd hub-demo1/AksFleetManager
32292  ls
32293  kubectl create ns apps\n
32294  kubectl apply -f clusterresourceplacement.yaml\n
32295  kubectl describe ClusterResourcePlacement appsrcp
32296  kubectl describe ClusterResourcePlacement appscrp
32297  kubectl get membercluster
32298  kubectl get membercluster --show-labels
32299  git status


Azure Kubernetes Fleet Manager (AKS Fleet Manager) allows for the management of multiple AKS clusters at scale. There are two types of AKS Fleet Manager instances: **hub** and **non-hub**.

- **Non-Hub AKS Fleet Manager Instance** - This acts solely as a grouping entity in Azure Resource Manager (ARM) without a central hub. It supports update orchestration but lacks workload orchestration and layer-4 load balancing. It does not incur additional costs.

- **Hub AKS Fleet Manager Instance** - This includes a managed AKS cluster that acts as a central hub. It stores and propagates Kubernetes resources, orchestrates workloads, and provides layer-4 load balancing. It incurs additional costs associated with the hub cluster.

## Comparison Chart

| Feature                        | Hub AKS Fleet Manager Instance | Non-Hub AKS Fleet Manager Instance |
|--------------------------------|--------------------------------|------------------------------------|
| **Hub Cluster Hosting**        | ✅                              | ❌                                  |
| **Update Orchestration**       | ✅                              | ✅                                  |
| **Workload Orchestration**     | ✅                              | ❌                                  |
| **Layer-4 Load Balancing**     | ✅                              | ❌                                  |
| **Billing Considerations**     | Costs associated with the hub  | No additional cost                 |
| **Conversion**                 | Cannot be downgraded           | Can be upgraded                    |

## Quickstart

1. Set resource group and cluster names in [vars.ps1](./vars.ps1)
2. Invoke [clusters.ps1](./clusters.ps1) to create 4 (1-node each) AKS clusters. Two will be assigned to each fleet instance.
3. Invoke [fleet-nonhub.ps1](./fleet-nonhub.ps1) to create a non-hub Fleet resource instance and associate the 1st and 2nd AKS clusters.
4. Invoke [fleet-hub.ps1](./fleet-hub.ps1) to create a hub Fleet cluster resource instance and associate the 3rd and 4th AKS clusters.

At this point, there are 2 Fleet instances with 2 AKS member clusters attached to each. 

## Non-Hub Cluster

The non-hub fleet manager in Azure is a configuration of Azure Kubernetes Fleet Manager that lets you group and manage multiple AKS clusters primarily for update orchestration—such as scheduling Kubernetes version and node image upgrades—without deploying a dedicated hub cluster. This simpler, hub-less setup streamlines update management by organizing clusters into update groups and monitoring their version states, while advanced features like resource propagation and multi-cluster load balancing are available only when a hub cluster is enabled.

## Hub Cluster

This cluster allows for additional functionality over the non-hub cluster, such as the ability to deploy workloads to a particular namespace and control the placement of those workloads across member clusters. 

### Member Clusters

Each member cluster is represented in the hub cluster as a `MemberCluster` resource and can be viewed by running `kubectl get memberclusters`. 

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: MemberCluster
metadata:
  labels:
    fleet.azure.com/location: eastus2
    fleet.azure.com/resource-group: rg-fleet-demo
    fleet.azure.com/subscription-id: SUBSCRIPTION_ID
  name: demo3cluster
spec:
  heartbeatPeriodSeconds: 15
  identity:
    kind: User
    name: CLUSTER_SAMI_GUID
```

### Resource Placement

After the `fleet-hub.ps1` script is invoked, you should be authenticated to the hub cluster (via Azure RBAC). The next steps are to create a namespace in the cluster, deploy a sample workload, and control the placement of the workloads in that namespace using a `ClusterResourcePlacement`.

```powershell
# create a namespace on the hub cluster called "apps"
kubectl create ns apps

# add a custom resource placement to apply to ALL member cluster for workloads on the "apps" namespace
kubectl apply -f clusterresourceplacement.yaml

# deploy a workload and LoadBalancer service
kubectl apply -f workload.yaml

# to remove the deployment
kubectl delete -f workload.yaml
```

After the workload is deployed, it will be available in the two member clusters (demo3cluster and demo4cluster), in addition to the LoadBalancer service and Azure Load Balancer created for it. In addition, removing the deployment/service resources from the `apps` namespace on the hub cluster will remove the same resources from these two member clusters.

### Controlling Resource Placement

The CRP used in the example above will propagate all resources within the namespace `apps` to their respective namespace on the member clusters. In order to control the placement of workloads to a set of member clusters, we can apply affinity using labels. 

```powershell
# add the label "env=prod" to the demo4cluster member
kubectl label membercluster demo4cluster env=prod

# add a custom resource placement to apply to only member clustes with the label env=prod
kubectl apply -f clusterresourceplacement-prod.yaml

# deploy a workload and LoadBalancer service
kubectl apply -f workload.yaml

# to remove the deployment
kubectl delete -f workload.yaml
```

After this workload is deployed, the resources are only applied to the docker4demo member cluster.

In addition, resources can be placed onto a specific set of clusters using the `spec.policy.placementType` value of "PickFixed" and supplying a list of `clusterNames`. See [clusterresourceplacement-fixed.yaml](./clusterresourceplacement-fixed.yaml) for an example.


### Placement types
The following placement types are available for controlling the number of clusters to which a specified Kubernetes resource needs to be propagated:

- [**PickFixed**](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-resource-propagation#pickfixed-placement-type) - Places the resource onto a specific list of member clusters by name.
- [**PickAll**](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-resource-propagation#pickall-placement-type) - Places the resource onto all member clusters, or all member clusters that meet a criteria. This policy is useful for placing infrastructure workloads, like cluster monitoring or reporting applications.
- [**PickN**](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-resource-propagation#pickn-placement-type) - The most flexible placement option and allows for selection of clusters based on affinity or topology spread constraints and is useful when spreading workloads across multiple appropriate clusters to ensure availability is desired.

### Placing Resources based on Metrics

The `MemberCluster` YAML example above has been shorted for brevity. In addition to placeing workloads/resources based on labels and names, there are additional properties that can also be used to control placement, such as cost and metrics based on the nodes. 

In the example below, various properties and resource indicators that can be targeted for placement. 

- `kubernetes-fleet.io/node-count` - Total nodes available in the cluster
- `kubernetes.azure.com/per-cpu-core-cost` - Cost of CPU/compute per core
- `kubernetes.azure.com/per-gb-memory-cost` - Cost of memory per GB

In addition, there are specific resource properties that can be accessed and used for placement decisions based on the current (or most recent heartbeat) CPU and memory that is `allocatable`, `available`, and how much `capacity` the VM/node SKU has.

```yaml
apiVersion: cluster.kubernetes-fleet.io/v1
kind: MemberCluster
metadata:
  labels:
    fleet.azure.com/location: eastus2
    fleet.azure.com/resource-group: rg-fleet-demo
    fleet.azure.com/subscription-id: SUBSCRIPTION_ID
  name: demo3cluster
spec:
  heartbeatPeriodSeconds: 15
  identity:
    kind: User
    name: CLUSTER_SAMI_GUID
status:
  properties:
    kubernetes-fleet.io/node-count:
      observationTime: "2025-04-02T14:07:13Z"
      value: "1"
    kubernetes.azure.com/per-cpu-core-cost:
      observationTime: "2025-04-02T14:07:13Z"
      value: "0.057"
    kubernetes.azure.com/per-gb-memory-cost:
      observationTime: "2025-04-02T14:07:13Z"
      value: "0.017"
  resourceUsage:
    allocatable:
      cpu: 1900m
      memory: 5160440Ki
    available:
      cpu: 478m
      memory: 3091960Ki
    capacity:
      cpu: "2"
      memory: 7097848Ki

```

### Summary of Example CRPs

- [**clusterresourceplacement.yaml**](./clusterresourceplacement.yaml) - Places resources specified by `resourceSelectors` in all member clusters, without conditions.
- [**clusterresourceplacement-prod.yaml**](./clusterresourceplacement-prod.yaml) - Places resources in member clusters matching the labels `env: prod`.
- [**clusterresourceplacement-fixed.yaml**](./clusterresourceplacement-fixed.yaml) - Places resources in exact member clusters specified by the `clusterNames` list.
- [**clusterresourceplacement-most-nodes.yaml**](./clusterresourceplacement-most-nodes.yaml) - Places resources in member clusters using the `kubernetes-fleet.io/node-count` property, in Descending order and picking the first cluster from this list. This will result in resources being placed on the cluster with the highest node count.
- [**clusterresourceplacement-exact-nodes.yaml**](./clusterresourceplacement-exact-nodes.yaml) - Places resources in member clusters using the `kubernetes-fleet.io/node-count` property, choosing (at most) 1 cluster with a `kubernetes-fleet.io/node-count` property value of 1. This will result in resources being placed only on the first cluster with only 1 node.

## Agents Installed 

- **fleet-hub-agent** - controller that creates and reconciles all the fleet-related CRs in the *hub* cluster.
- **fleet-member-agent** - controller that creates and reconciles all the fleet-related CRs in the *member* cluster.

## Common CRDs

- **`MemberCluster`** - Represents a Kubernetes cluster that is part of the managed fleet. It provides metadata and configuration details required for integrating and managing the cluster within the fleet, including connectivity, resource usage, and status information.
- **`ClusterResourcePlacement`** - Used to define how and where workloads are distributed across a fleet of clusters. It allows administrators to specify policies and constraints for deploying resources, ensuring efficient utilization and adherence to placement strategies across the managed clusters.
- **`MultiClusterService`** - Used to manage and expose services across multiple clusters within the fleet. It facilitates the seamless routing of traffic to the appropriate cluster, enabling consistent and reliable service access across the entire fleet.

To view the resources in the cluster, invoke the following commands:

```powershell
# list member cluster CRD resources
kubectl get memberclusters

# list the custom placements
kubectl get clusterresourceplacements

# list the multi-cluster services
kubectl get multiclusterservices

# list fleet-specific resources
kubectl api-resources | findstr /c:fleet /i
```


## Fleet Hub Update Stages and Groups

![](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/media/conceptual-update-orchestration.png#lightbox)

### Definitions

- **Update Run** - Represents an update that is to be applied to a collection of AKS clusters

## Links

- [Azure Kubernetes Fleet Manager and member clusters](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-fleet)
- [Choosing an Azure Kubernetes Fleet Manager option](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-choosing-fleet)
- [Fleet - Github](https://github.com/Azure/fleet)
- [Fleet Networking - Github](https://github.com/Azure/fleet-networking)
- [Intelligent cross-cluster Kubernetes resource placement using Azure Kubernetes Fleet Manager](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/intelligent-resource-placement)