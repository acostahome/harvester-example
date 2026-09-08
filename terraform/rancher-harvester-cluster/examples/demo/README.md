# Create single node Harvester cluster in Rancher using Terraform

Download a kubeconfig from the Rancher UI into your home directory, name it `homelab-rancher.yaml`. Also download one for the imported Harvester cluster and name it `homelab-harvester.yaml`. Then run:

```sh
HARVESTER_CLUSTER_ID=$(kubectl --kubeconfig "$HOME/homelab-rancher.yaml" get clusters.management.cattle.io -oyaml | yq '.items[] | select(.spec.displayName=="homelab") | .metadata.name')
RANCHER_PASSWORD="m8THD8jL\!1fR9C7v"
export RANCHER_URL="https://rancher.home.internal"
export RANCHER_TOKEN_KEY=$(curl -s "$RANCHER_URL/v1-public/login" \
  -X POST \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  --data-raw "{\"type\":\"localProvider\",\"username\":\"admin\",\"password\":\"$RANCHER_PASSWORD\"}" |
  jq -r '.token')
kubectl --kubeconfig "$HOME/homelab-harvester.yaml" create ns demo-cluster
CLUSTER_NAME="demo-cluster"
curl -s -X POST "$RANCHER_URL/k8s/clusters/${HARVESTER_CLUSTER_ID}/v1/harvester/kubeconfig" \
  -H 'Content-Type: application/json' \
  -u ${RANCHER_TOKEN_KEY} \
  -d '{"clusterRoleName": "harvesterhci.io:cloudprovider", "namespace": "demo-cluster", "serviceAccountName": "'$CLUSTER_NAME'"}' |
  tr -d '"' | 
  sed 's/\\n/\n/g' \
  > files/${CLUSTER_NAME}-kubeconfig
```

Beware that a token for Rancher created this way is good for only a single day. Alternatively, create an API key in the UI and it will be good for 30 days.

Then to run Terraform:

```sh
terraform apply -auto-approve
```