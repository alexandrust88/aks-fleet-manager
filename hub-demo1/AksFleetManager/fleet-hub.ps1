. .\vars.ps1

$fleet = "fleethub"

# create the hub fleet manager (using --enable-hub)
az fleet create -g $group -n $fleet -l eastus2 --enable-hub

# get the cluster IDs
$cluster3id = az aks show -n $cluster3 -g $group --query id -o tsv
$cluster4id = az aks show -n $cluster4 -g $group --query id -o tsv

# Join the member clusters
az fleet member create -g $group -f $fleet -n $cluster3 --member-cluster-id $cluster3id
az fleet member create -g $group -f $fleet -n $cluster4 --member-cluster-id $cluster4id

# get credentials
az fleet get-credentials -n $fleet -g $group
kubelogin convert-kubeconfig -l azurecli

# role creation ("Azure Kubernetes Fleet Manager RBAC Cluster Admin" / 18ab4d3d-a1bf-4477-8ad9-8359bc988f69)
$fleetId = az fleet show -n $fleet -g $group --query id -o tsv
$myId = az ad signed-in-user show --query id -o tsv

az role assignment create --assignee $myId --role 18ab4d3d-a1bf-4477-8ad9-8359bc988f69 --scope $fleetId

# list the fleet members
az fleet member list -g $group -f $fleet -o table