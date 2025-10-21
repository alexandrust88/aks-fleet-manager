. .\vars.ps1

$fleet = "fleetnonhub"

# ensure az extension is added
#az extension add --name fleet

# create the non-hub fleet manager
az fleet create -g $group -n $fleet -l eastus2

# get the cluster IDs
$cluster1id = az aks show -n $cluster1 -g $group --query id -o tsv
$cluster2id = az aks show -n $cluster2 -g $group --query id -o tsv

# Join the member clusters
az fleet member create -g $group -f $fleet -n $cluster1 --member-cluster-id $cluster1id
az fleet member create -g $group -f $fleet -n $cluster2 --member-cluster-id $cluster2id

# list the fleet members
az fleet member list -g $group -f $fleet -o table