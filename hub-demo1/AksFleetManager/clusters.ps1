. .\vars.ps1

# create the RG
az group create -n $group -l eastus2

# create two clusters
az aks create -n $cluster1 -g $group -c 1
az aks create -n $cluster2 -g $group -c 1
az aks create -n $cluster3 -g $group -c 1
az aks create -n $cluster4 -g $group -c 2

# authenticate to the clusters
az aks get-credentials -n $cluster1 -g $group --overwrite-existing
az aks get-credentials -n $cluster2 -g $group --overwrite-existing
az aks get-credentials -n $cluster3 -g $group --overwrite-existing
az aks get-credentials -n $cluster4 -g $group --overwrite-existing