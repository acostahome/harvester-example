# Bootstrap Resources

This will install all of the remaining infrastructure-layer resources that are not pre-bundled, including networks and a virtual machine image for openSUSE Leap 16.0.

## Setting up Fleet to Manage Harvester

To be able to manage cluster workloads on the Harvester cluster itself, as opposed to guest clusters created by Rancher, enable the baremetal container workload feature in Rancher. First, download a kubeconfig from the Rancher UI, then use it. To enable the feature:

```sh
kubectl patch feature harvester-baremetal-container-workload -p '{"spec":{"value":true}}' --type merge
```

Alternatively, this may also be done through the UI.

To create a cluster group that Fleet can use:

```sh
HARVESTER_CLUSTER_ID=$(kubectl get clusters.management.cattle.io -oyaml | 
  yq '.items[] | select(.spec.displayName=="homelab") | .metadata.name')
kubectl label clusters.fleet.cattle.io -n fleet-default "$HARVESTER_CLUSTER_ID" type=harvester-host location=homelab
kubectl create -f -<<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: ClusterGroup
metadata:
  name: homelab-harvester
  namespace: fleet-default
spec:
  selector:
    matchLabels:
      location: homelab
      type: harvester-host
EOF
```

## Creating the GitRepo

We need to create an ssh key auth secret for Rancher to be able to use Fleet from our private Git repo:

```sh
kubectl create -f -<<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ssh-auth-github
  namespace: fleet-default
data:
  ssh-privatekey: $(base64 -w0 <"$HOME/.ssh/id_ed25519")
type: kubernetes.io/ssh-auth
EOF
```

Then create a `GitRepo`:

```sh
kubectl create -f -<<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: homelab-harvester-bootstrap
  namespace: fleet-default
spec:
  repo: git@github.com:acostahome/harvester-example.git
  branch: main
  clientSecretName: ssh-auth-github
  bundles:
    - base: manifests/harvester/images
    - base: manifests/harvester/networks
  targets:
    - name: harvester
      clusterGroup: homelab-harvester
EOF
```

This targets the cluster group we created earlier.