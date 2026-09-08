# csi-driver-nfs

For the `csi-driver-nfs`, we will use a separate `GitRepo` that deploys the single Helm chart:

```sh
kubectl create -f -<<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: homelab-harvester-csi-driver-nfs
  namespace: fleet-default
spec:
  repo: git@github.com:acostahome/harvester-example.git
  branch: main
  clientSecretName: ssh-auth-github
  paths:
    - manifests/harvester/csi-driver-nfs
  targets:
    - name: harvester
      clusterGroup: homelab-harvester
EOF
```