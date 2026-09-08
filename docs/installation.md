What is the full description of the feature set that was quoted versus the free version of Harvester.
Want to see how to install a host/node.
Want to see how to attach external NAS (NFS) storage to a cluster for use of all the VMs and K8s things.
Want to see RBAC for the system and especially IDM/LDAP for the clusters and pods and differences for the free one.
Want to see how to put 2 or more hosts together into a cluster
Want to see how to manage more than one cluster. (Is that the same thing as #5?)
Want to see how to “admin” a cluster using the vCenter analog tool – Rancher Manager maybe?
Want to see the maintenance mode aka drain and fix.
Want to see how to put on a container or deploy via helm after the hosts are going.
Want to see how Longhorn gets setup using the NFS storage (recall we use Dell Isilons) and how that works.
Want to see management of the RKE2 pods.
Want to see how secrets management works relative to pods to/from Vault.
Want to know about compatibility with CONSUL enterprise.
We’ve been using the free version of RKE2 for a long time, so want to see if the workflows would change anything for the better using the paid/Prime version.
Explain what Carbide actually gets us and can do as the customer and security folks will be all over that like a hobo on a hamburger.

# Lab Environment Installation Instructions

# PKI

Harvester and Rancher give you a lot of freedom to configure certificates however you wish. They will create self-signed certificates for you by default, or you can request them from Let's Encrypt if on the public Internet. Or, you can pre-stage server certificates acquired out-of-band, which is typically what military and IC customers will do since they need to use certificates issued by a private CA. For my homelab, I have a private CA created on the command line using `openssl`. The following configuration is sufficient for Harvester and Rancher:

`ca.conf`
```ini
[req]
distinguished_name = req_distinguished_name
prompt             = no
x509_extensions    = ca_x509_extensions

[ca_x509_extensions]
authorityKeyIdentifier = keyid:always, issuer:always
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash

[req_distinguished_name]
C  = US
CN = CA
L  = Dallas
ST = TX

[harvester]
distinguished_name = harvester_distinguished_name
prompt             = no
req_extensions     = harvester_req_extensions

[harvester_distinguished_name]
C  = US
CN = harvester.lab.internal
L  = Dallas
ST = TX

[harvester_req_extensions]
basicConstraints     = CA:FALSE
extendedKeyUsage     = clientAuth, serverAuth
keyUsage             = critical, digitalSignature, keyEncipherment
nsCertType           = client, server
nsComment            = "Harvester Server Certificate"
subjectAltName       = DNS:harvester.lab.internal, IP:10.240.0.10
subjectKeyIdentifier = hash

[rancher]
distinguished_name = rancher_distinguished_name
prompt             = no
req_extensions     = rancher_req_extensions

[rancher_distinguished_name]
C  = US
CN = rancher.home.internal
L  = Dallas
ST = TX

[rancher_req_extensions]
basicConstraints     = CA:FALSE
extendedKeyUsage     = clientAuth, serverAuth
keyUsage             = critical, digitalSignature, keyEncipherment
nsCertType           = client, server
nsComment            = "Rancher Server Certificate"
subjectAltName       = DNS:rancher.home.internal
subjectKeyIdentifier = hash
```

Generate the CA like so:

```sh
openssl genrsa -out ca.key 4096
openssl req -x509 -new -sha512 -noenc \
  -key ca.key -days 3653 \
  -config ca.conf \
  -out ca.crt
```

Then issue certificates for Harvester and Rancher:

```sh
openssl genrsa -out harvester.key 4096
openssl req -new -key harvester.key -sha256 \
  -config ca.conf -section harvester \
  -out harvester.csr
openssl x509 -req -days 365 -in harvester.csr \
  -copy_extensions copyall \
  -sha256 -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out harvester.crt

openssl genrsa -out rancher.key 4096
openssl req -new -key rancher.key -sha256 \
  -config ca.conf -section rancher \
  -out rancher.csr
openssl x509 -req -days 365 -in rancher.csr \
  -copy_extensions copyall \
  -sha256 -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out rancher.crt
```

Similar commands are used to issue certificates for other internal services such as the private container registry, Keycloak, etc., and the CA cert is added to the trust stores of all hosts and browsers.

The downside to issuing certificates out-of-band from a private CA is that they will not automatically be renewed, so you must monitor for expiration manually and request renewals from the CA when the time is near. Cert Manager, in concert with any CA that offers an ACME endpoint, can automate this, but this requires the ACME server be able to reach either your application or an authoritative DNS nameserver for the domain you are using.

# Artifact Pre-staging

First, we will acquire all of the container images and Helm charts needed to deploy the applications we want inside of an airgap. Prerequisites are:

- Hauler CLI
- Helm CLI
- Credentials to Carbide Secure Registry
- An internal registry to copy to

Internal private registry is provided by TrueNAS, using the `distribution` app, which is a simple single-container Docker registry2 with http basic auth in front of it.

Carbide credentials will come with an eval license or subscription.

For Hauler:

```sh
curl -fsLS https://get.hauler.dev | sudo bash
```

For Helm:

```sh
curl -fsLS https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | sudo bash
```

Login to Carbide registry:

```sh
hauler login registry.ranchercarbide.dev -u $CARBIDE_USER -p $CARBIDE_PASSWORD
helm registry login registry.ranchercarbide.dev -u $CARBIDE_USER -p $CARBIDE_PASSWORD
```

Login to internal private registry:

```sh
hauler login registry.lab.internal:5000 -u $REGISTRY_USER -p $REGISTRY_PASSWORD
helm registry login registry.lab.internal:5000 -u $REGISTRY_USER -p $REGISTRY_PASSWORD
```

# Harvester Lab Environment

This is highly hardware-specific. In my case, I used a Minisforum GK41 running SL Micro 6.2 as a bastion host and gateway serving DHCP and DNS to the Harvester nodes, which are three Minisforum MSA2s with 64GiB RAM, a 1TiB OS disk, and 4TiB data disk each.

## Gateway Host

The gateway is responsible for the subnet `10.240.0.0/16`, with the rest of the house on `192.168.0.0/16`. Hosts inside of the `10.240.0.0/16` subnet are "airgapped" by creating the following `iptables` rules on the gateway:

```
*filter
:INPUT ACCEPT [249877:375870652]
:FORWARD ACCEPT [1052922:552460047]
:OUTPUT ACCEPT [155111:347679165]
-A INPUT -s 10.240.0.0/16 -d 10.240.0.0/16 -j RETURN
-A INPUT -s 10.240.0.0/16 -d 192.168.0.0/16 -j RETURN
-A INPUT -s 10.240.0.0/16 -j DROP
-A FORWARD -i enp3s0.10 -o enp3s0.20 -m state --state NEW -j DROP
-A FORWARD -i enp3s0.20 -o enp3s0.10 -m state --state NEW -j DROP
COMMIT
*nat
:PREROUTING ACCEPT [42060:2533713]
:INPUT ACCEPT [11575:868067]
:OUTPUT ACCEPT [4268:314026]
:POSTROUTING ACCEPT [33851:1915024]
-A POSTROUTING -s 10.240.0.0/16 -d 192.168.0.0/16 -j MASQUERADE
COMMIT
```

This allow traffic to its own subnet, the main home subnet, and segregates vlan 10 from vlan 20, dropping all other traffic. Hosts in the "airgap" subnet are still accessible via static routes in my other home routers from the rest of the house.

The gateway runs `dnsmasq` with following partial configuration:

`/etc/dnsmasq.d/localnet.conf`
```ini
interface=enp3s0
domain=edge.internal
dhcp-range=10.240.0.30,10.240.0.254,255.255.255.0
enable-tftp
tftp-root=/srv/tftpboot

# Netgear GS108Tv3 switch
dhcp-host=28:94:01:7F:16:67,10.240.0.3

# Minisforum MS-A2 hvst-1, hvst-2, hvst-3
# enp3sp
dhcp-host=38:05:25:36:33:13,hvst-1,10.240.0.11,set:hvst-1
dhcp-host=38:05:25:36:34:23,hvst-2,10.240.0.12,set:hvst-2
dhcp-host=38:05:25:36:34:3b,hvst-3,10.240.0.13,set:hvst-3

# PXE config
dhcp-userclass=set:ipxe,iPXE
dhcp-boot=tag:!ipxe,ipxe.efi
dhcp-boot=tag:hvst-1,tag:ipxe,http://10.240.0.2:8080/hvst-1-ipxe
dhcp-boot=tag:hvst-2,tag:ipxe,http://10.240.0.2:8080/hvst-2-ipxe
dhcp-boot=tag:hvst-3,tag:ipxe,http://10.240.0.2:8080/hvst-3-ipxe
```

`podman` is used to run `nginx` serving the iPXE scripts and Harvester installation artifacts. An example of how to do this:

```sh
mkdir $HOME/html
podman run -d --name nginx -p 8080:80 -v $HOME/html:/usr/share/nginx/html:ro nginx
```

An example iPXE script:

```sh
#!ipxe
dhcp
kernel http://10.240.0.2:8080/harvester-v1.8.2-govt.1-vmlinuz-amd64 \
    ip=dhcp \
    console=tty1 \
    net.ifnames=1 \
    rd.cos.disable \
    rd.noverifyssl \
    root=live:http://10.240.0.2:8080/harvester-v1.8.2-govt.1-rootfs-amd64.squashfs \
    harvester.install.config_url=http://10.240.0.2:8080/hvst-1-config.yaml \
    harvester.install.skipchecks=true \
    harvester.install.automatic=true
initrd http://10.240.0.2:8080/harvester-v1.8.2-govt.1-initrd-amd64
boot
```

This is the first host, which runs the installer in create mode, using the following partial configuration:

```yaml
scheme_version: 1
token: $TOKEN
os:
  ntp_servers:
    - 192.168.1.1
  password: $PASSWORD
  ssh_authorized_keys:
    - $MY_PUBKEYS
    - ...
install:
  addons:
    kubeovn_operator:
      enabled: true
    pcidevices_controller:
      enabled: true
    rancher_monitoring:
      enabled: true
    vm_import_controller:
      enabled: true
  data_disk: /dev/nvme1n1
  device: /dev/nvme0n1
  iso_url: http://10.240.0.2:8080/harvester-v1.8.2-govt.1-amd64.iso
  management_interface:
    interfaces:
      - name: enp3s0
    method: dhcp
  mode: create
  vip: 10.240.0.10
  vip_mode: static
  wipe_all_disks: true
```

An example for a second cluster node to join this new cluster:

```yaml
scheme_version: 1
server_url: https://10.240.0.10:443
token: $TOKEN
os:
  ntp_servers:
    - 192.168.1.1
  password: $PASSWORD
  ssh_authorized_keys:
    - $MY_PUBKEYS
    - ...
install:
  data_disk: /dev/nvme1n1
  device: /dev/nvme0n1
  iso_url: http://10.240.0.2:8080/harvester-v1.8.2-govt.1-amd64.iso
  management_interface:
    interfaces:
      - name: enp3s0
    method: dhcp
  mode: join
  wipe_all_disks: true
```

There is a bit more to the installation configuration in order to automate PKI and private registry setup specific to my homelab, but these are the minimal requirements for a fully-unattended installation. Because we only want to use PXE for the installer and normal boot afterward will boot from disk, the BIOS for each Harvester node was first configured to use USB, NVME, then Network, in that order. I used a live Arch Iso to first boot and see what interface and disk device names would be, in order to put those into the installer configuration. Beware that if you have more than two disks, the NVME enumeration order in Linux 6+ is not stable and you will need to use `/dev/disk/by-id/` or `/dev/disk/by-path/`.

The installer flow looks like this:

```
UEFI Firmware
  │
  ▼  DHCP request (no user-class)
dnsmasq  ──→  responds with ipxe.efi (TFTP)
  │
  ▼  TFTP download
ipxe.efi executes
  │
  ▼  DHCP request (user-class: iPXE)
dnsmasq  ──→  responds with boot script URL (HTTP)
  │
  ▼  HTTP fetch boot script
iPXE executes script
  │
  ▼  HTTP download kernel + initrd
Harvester installer runs
```

To stage the iPXE executable:

```sh
curl -fsLS https://boot.ipxe.org/x86_64-efi/ipxe.efi -o $HOME/html/ipxe.efi
```

The Harvester installer artifacts can be downloaded from the portal UI at <https://portal.ranchercarbide.dev/product/harvester>, ensuring you select the correct architecture and version from the drop down menu. This may also be automated, doing something like the following (insert real Carbide username and password):

```sh
REG_URL="registry.ranchercarbide.dev"
HVST_VERS="1.8.2-govt.1"
CARBIDE_USER=""
CARBIDE_PASSWORD=""
CARBIDE_TOKEN=$(curl -sL -u "$CARBIDE_USER:$CARBIDE_PASSWORD" \
  "https://${REG_URL}/service/token?service=harbor-registry" | 
  jq -r '.token')

# ISO
DIGEST=$(curl -H "Accept: application/vnd.oci.image.manifest.v1+json" -H "Authorization: Bearer $CARBIDE_TOKEN" -sL \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-amd64.iso/manifests/v${HVST_VERS}" |
  jq -r '.layers[0].digest')

curl -H "Accept: application/vnd.oci.image.layer.v1.tar" -H "Authorization: Bearer $CARBIDE_TOKEN" -L \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-amd64.iso/blobs/${DIGEST}" \
  -o "$HOME/html/harvester-v${HVST_VERS}-amd64.iso"

# initrd
DIGEST=$(curl -H "Accept: application/vnd.oci.image.manifest.v1+json" -H "Authorization: Bearer $CARBIDE_TOKEN" -sL \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-initrd-amd64/manifests/v${HVST_VERS}" |
  jq -r '.layers[0].digest')

curl -H "Accept: application/vnd.oci.image.layer.v1.tar" -H "Authorization: Bearer $CARBIDE_TOKEN" -L \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-initrd-amd64/blobs/${DIGEST}" \
  -o "$HOME/html/harvester-v${HVST_VERS}-initrd-amd64"

# kernel
DIGEST=$(curl -H "Accept: application/vnd.oci.image.manifest.v1+json" -H "Authorization: Bearer $CARBIDE_TOKEN" -sL \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-vmlinuz-amd64/manifests/v${HVST_VERS}" |
  jq -r '.layers[0].digest')

curl -H "Accept: application/vnd.oci.image.layer.v1.tar" -H "Authorization: Bearer $CARBIDE_TOKEN" -L \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-vmlinuz-amd64/blobs/${DIGEST}" \
  -o "$HOME/html/harvester-v${HVST_VERS}-vmlinuz-amd64"

# rootfs
DIGEST=$(curl -H "Accept: application/vnd.oci.image.manifest.v1+json" -H "Authorization: Bearer $CARBIDE_TOKEN" -sL \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-rootfs-amd64.squashfs/manifests/v${HVST_VERS}" |
  jq -r '.layers[0].digest')

curl -H "Accept: application/vnd.oci.image.layer.v1.tar" -H "Authorization: Bearer $CARBIDE_TOKEN" -L \
  "https://${REG_URL}/v2/carbide/harvester/harvester-v${HVST_VERS}-rootfs-amd64.squashfs/blobs/${DIGEST}" \
  -o "$HOME/html/harvester-v${HVST_VERS}-rootfs-amd64.squashfs"
```

Whenever new artifacts are added to be served by `nginx` via `podman`, run the following:

```sh
sudo chcon -Rv --type=container_file_t html/
```

Otherwise, SELinux will deny access to the files regardless of the owner and mode. SL Micro runs with SELinux Enforcing by default.

# Harvester Installation

Once all of this is setup, creating a three-node cluster is as simple as booting the first node, waiting for the cluster to become ready, then booting the other two nodes to join.

Alternatively, the ISO may be mounted via USB, BlueRay, iLO, iDRAC, or any other BMC/IPMI provider or remote KVM that offers virtual media, and installation can be done interactively. Instructions for doing this, along with a video, may be found at [Installation > ISO Installation](https://docs.harvesterhci.io/v1.8/install/index).

# Rancher Installation

## Overview

There are many options to run Rancher. Generally, a three-node control-plane only cluster that runs only Rancher is advised. This may be done using virtual machines created in Harvester. My lab uses a bare-metal RKE2 cluster installed onto three Minisforum UM700s running SL Micro 6.2. The default non-root user is named `rancher`, same as the airgap gateway.

## RKE2

### Installation Artifacts

Instead of using the `hauler` `--products` flag for RKE2, which will currently pull *all* RKE2 images, we use a filtering script to only grab what we want. It looks like this:

```sh
#!/bin/bash

set -euo pipefail

WORKDIR=$(mktemp -d)
RKE2_VERSION="$1"

pushd "${WORKDIR}"

curl -fsLSO "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-core.linux-amd64.txt"
curl -fsLSO "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-cilium.linux-amd64.txt"
curl -fsLSO "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-harvester.linux-amd64.txt"
curl -fsLSO "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-traefik.linux-amd64.txt"

cat rke2-images-*.txt | sed -E '/aws|azure/d' | sed 's/docker\.io/registry\.ranchercarbide\.dev/g' | sort -u \
  > rke2-images.txt

popd

cat <<EOF > rke2-manifest.yaml
apiVersion: content.hauler.cattle.io/v1
kind: Images
metadata:
  name: carbide-rke2-images
spec:
  images:
EOF

while read -r img; do
  echo "    - name: ${img}"
done < "${WORKDIR}/rke2-images.txt" >> rke2-manifest.yaml

rm -r "${WORKDIR}"

hauler store sync --filename rke2-manifest.yaml --platform linux/amd64
hauler store copy registry://registry.lab.internal:5000
rm -rf store
rm -f rke2-manifest.yaml
```

For versioning, we have to rely upon the Harvester support matrix. Harvester 1.8.x is compatible with Rancher 2.14.x, which in turn can run on RKE2 up to 1.35.x. We thus grab the latest RKE2 1.35.x:

```sh
RKE2_VERSION=$(curl -fsLS https://update.rke2.io/v1-release/channels | jq -r '.data[] | select(.id=="v1.35").latest')
./rke2-images.sh "$RKE2_VERSION"
```

### Configuration Files

The following configuration files are added to each host:

`/etc/rancher/rke2/config.yaml`
```yaml
cni: cilium
disable:
  - rke2-ingress-nginx
disable-kube-proxy: true
embedded-registry: true
kube-apiserver-arg:
  - tls-min-version=VersionTLS13
  - audit-log-path=/var/lib/rancher/rke2/server/logs/audit.log
  - anonymous-auth=false
  - authorization-mode=RBAC,Node
  - audit-log-maxage=30
  - audit-log-mode=blocking-strict
kubelet-arg:
  - anonymous-auth=false
  - read-only-port=0
  - authorization-mode=Webhook
  - streaming-connection-idle-timeout=5m
  - protect-kernel-defaults=true
kube-controller-manager-arg:
  - bind-address=127.0.0.1
  - tls-min-version=VersionTLS13
  - use-service-account-credentials=true
kube-scheduler-arg:
  - tls-min-version=VersionTLS13
pod-security-admission-config-file: /etc/rancher/rke2/rancher-pss.yaml
profile: cis
system-default-registry: registry.lab.internal:5000
secrets-encryption: true
tls-san:
  - 192.168.3.10
  - rancher-api.home.internal
```

Only this file differs per host. The cluster initializer should look exactly like this, whereas the two subsequent nodes that join an existing cluster need to have the following added:

```yaml
server: https://192.168.3.10:9345
token: $TOKEN
```

Where `$TOKEN` is obtained after RKE2 starts on the initializer host by running `cat /var/lib/rancher/rke2/server/token`. Alternatively, a token may be pre-populated using any sufficiently random and long string that is the same on all three hosts, if you wish to start them simultaneously. This may be preferable when using virtual machines provisioned with Terraform or some other automation tool.

`/etc/rancher/rke2/audit-policy.yaml`
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # The following requests were manually identified as high-volume and low-risk,
  # so drop them.
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
      - group: "" # core
        resources: ["endpoints", "services", "services/status"]
  - level: None
    # Ingress controller reads 'configmaps/ingress-uid' through the unsecured port.
    # TODO(#46983): Change this to the ingress controller service account.
    users: ["system:unsecured"]
    namespaces: ["kube-system"]
    verbs: ["get"]
    resources:
      - group: "" # core
        resources: ["configmaps"]
  - level: None
    users: ["kubelet"] # legacy kubelet identity
    verbs: ["get"]
    resources:
      - group: "" # core
        resources: ["nodes", "nodes/status"]
  - level: None
    userGroups: ["system:nodes"]
    verbs: ["get"]
    resources:
      - group: "" # core
        resources: ["nodes", "nodes/status"]
  - level: None
    users:
      - system:kube-controller-manager
      - system:cloud-controller-manager
      - system:kube-scheduler
      - system:serviceaccount:kube-system:endpoint-controller
    verbs: ["get", "update"]
    namespaces: ["kube-system"]
    resources:
      - group: "" # core
        resources: ["endpoints"]
  - level: None
    users: ["system:apiserver"]
    verbs: ["get"]
    resources:
      - group: "" # core
        resources: ["namespaces", "namespaces/status", "namespaces/finalize"]
  - level: None
    users: ["cluster-autoscaler"]
    verbs: ["get", "update"]
    namespaces: ["kube-system"]
    resources:
      - group: "" # core
        resources: ["configmaps", "endpoints"]
  # Don't log HPA fetching metrics.
  - level: None
    users:
      - system:kube-controller-manager
      - system:cloud-controller-manager
    verbs: ["get", "list"]
    resources:
      - group: "metrics.k8s.io"
  # Don't log these read-only URLs.
  - level: None
    nonResourceURLs:
      - /healthz*
      - /version
      - /swagger*
  # Don't log events requests because of performance impact.
  - level: None
    resources:
      - group: "" # core
        resources: ["events"]
  # node and pod status calls from nodes are high-volume and can be large, don't log responses for expected updates from nodes
  - level: Request
    users: ["kubelet", "system:node-problem-detector", "system:serviceaccount:kube-system:node-problem-detector"]
    verbs: ["update", "patch"]
    resources:
      - group: "" # core
        resources: ["nodes/status", "pods/status"]
    omitStages:
      - "RequestReceived"
  - level: Request
    userGroups: ["system:nodes"]
    verbs: ["update", "patch"]
    resources:
      - group: "" # core
        resources: ["nodes/status", "pods/status"]
    omitStages:
      - "RequestReceived"
  # deletecollection calls can be large, don't log responses for expected namespace deletions
  - level: Request
    users: ["system:serviceaccount:kube-system:namespace-controller"]
    verbs: ["deletecollection"]
    omitStages:
      - "RequestReceived"
  # Secrets, ConfigMaps, TokenRequest and TokenReviews can contain sensitive & binary data,
  # so only log at the Metadata level.
  - level: Metadata
    resources:
      - group: "" # core
        resources: ["secrets", "configmaps", "serviceaccounts/token"]
      - group: authentication.k8s.io
        resources: ["tokenreviews"]
    omitStages:
      - "RequestReceived"
  # Get responses can be large; skip them.
  - level: Request
    verbs: ["get", "list", "watch"]
    resources:
      - group: "" # core
      - group: "admissionregistration.k8s.io"
      - group: "apiextensions.k8s.io"
      - group: "apiregistration.k8s.io"
      - group: "apps"
      - group: "authentication.k8s.io"
      - group: "authorization.k8s.io"
      - group: "autoscaling"
      - group: "batch"
      - group: "certificates.k8s.io"
      - group: "extensions"
      - group: "metrics.k8s.io"
      - group: "networking.k8s.io"
      - group: "node.k8s.io"
      - group: "policy"
      - group: "rbac.authorization.k8s.io"
      - group: "scheduling.k8s.io"
      - group: "storage.k8s.io"
    omitStages:
      - "RequestReceived"
  # Default level for known APIs
  - level: RequestResponse
    resources:
      - group: "" # core
      - group: "admissionregistration.k8s.io"
      - group: "apiextensions.k8s.io"
      - group: "apiregistration.k8s.io"
      - group: "apps"
      - group: "authentication.k8s.io"
      - group: "authorization.k8s.io"
      - group: "autoscaling"
      - group: "batch"
      - group: "certificates.k8s.io"
      - group: "extensions"
      - group: "metrics.k8s.io"
      - group: "networking.k8s.io"
      - group: "node.k8s.io"
      - group: "policy"
      - group: "rbac.authorization.k8s.io"
      - group: "scheduling.k8s.io"
      - group: "storage.k8s.io"
    omitStages:
      - "RequestReceived"
  # Default level for all other requests.
  - level: Metadata
    omitStages:
      - "RequestReceived"
```

Please note that audit policy is specific to local requirements. Harvester, for instance, defaults to logging all request and response metadata and nothing else for all resources in all namespaces. My audit policy is copied from the default for hosted Google Kubernetes Engine. We have no "official" recommendation. Play around with levels and see what is valuable and what is not.

`/etc/rancher/rke2/rancher-pss.yaml`
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "restricted"
        enforce-version: "latest"
        audit: "restricted"
        audit-version: "latest"
        warn: "restricted"
        warn-version: "latest"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces: [calico-apiserver,
                     calico-system,
                     cattle-alerting,
                     cattle-csp-adapter-system,
                     cattle-elemental-system,
                     cattle-epinio-system,
                     cattle-externalip-system,
                     cattle-fleet-local-system,
                     cattle-fleet-system,
                     cattle-gatekeeper-system,
                     cattle-global-data,
                     cattle-global-nt,
                     cattle-impersonation-system,
                     cattle-istio,
                     cattle-istio-system,
                     cattle-logging,
                     cattle-logging-system,
                     cattle-monitoring-system,
                     cattle-neuvector-system,
                     cattle-prometheus,
                     cattle-provisioning-capi-system,
                     cattle-resources-system,
                     cattle-sriov-system,
                     cattle-system,
                     cattle-ui-plugin-system,
                     cattle-windows-gmsa-system,
                     cert-manager,
                     cis-operator-system,
                     endpoint-copier-operator,
                     fleet-default,
                     fleet-local,
                     ingress-nginx,
                     istio-system,
                     kube-node-lease,
                     kube-public,
                     kube-system,
                     longhorn-system,
                     metallb-system,
                     rancher-alerting-drivers,
                     security-scan,
                     tigera-operator]
```

This is copied from Rancher installation docs to allow all of the namespaces needed by Rancher and RKE2 control plane components to perform privileged operations. Pods in all other namespaces run restricted. This adds `metallb-system` in order to be able to use MetalLB for a bare metal load balancer, which also requires privileges pods to configure host network.

`/etc/rancher/rke2/registries.yaml`
```yaml
mirrors:
  docker.io:
    endpoint:
      - "https://registry.lab.internal:5000"
  registry.rancher.com:
    endpoint:                                                                                                                        - "https://registry.lab.internal:5000"
  registry.suse.com:
    endpoint:
      - "https://registry.lab.internal:5000"
configs:
  "registry.lab.internal:5000":
    auth:
      username: rancher
      password: $PASSWORD
```

This uses the private registry in TrueNAS, using a basic auth user configured in the app panel, specifically for use by Rancher and Rancher-managed Kubernetes clusters.

`/etc/sysctl.d/60-rke2-cis.conf`
```yaml
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
```

These are the required sysctls for `kubelet` to work. By default, `kubelet` will set these itself, but when running a hardened cluster, compliant with CIS and STIG requirements, we must not allow `kubelet` to modify host kernel settings, so we set these ourselves beforehand.

Finally, a user for `etcd` is created, also to comply with hardening requirements:

```sh
sudo useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U
```

### Component Configuration

We change the default values for Cilium to allow it to be used as a Gateway provider and to run in `kube-proxy` replacement mode. This is done by pre-placing the following file for the HelmChart CRD addon:

`/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml`
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    bpf:
      distributedLRU:
        enabled: true
      mapDynamicSizeRatio: 0.08
      masquerade: true
      preallocateMaps: true
    bpfClockProbe: true
    envoy:
      enabled: true
    gatewayAPI:
      enabled: true
    routingMode: tunnel
    kubeProxyReplacement: true
    k8sServiceHost: localhost
    k8sServicePort: "6443"
```

### Additional Manifests

For the sake of simplicity, the manifests needed to deploy MetalLB and SUSE's Endpoint Copier Operator and pre-placed, along with the MetalLB CRs to deploy a VIP for the API server:

`/var/lib/rancher/rke2/server/manifests/endpoint-copier-operator.yaml`
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: endpoint-copier-operator
  namespace: kube-system
spec:
  bootstrap: true
  chartContent: |-
    ...
  createNamespace: true
  targetNamespace: endpoint-copier-operator
```

`/var/lib/rancher/rke2/server/manifests/metallb.yaml`
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: metallb
  namespace: kube-system
spec:
  bootstrap: true
  chartContent: |-
    ...
  createNamespace: true
  targetNamespace: metallb-system
```

Each of these embeds the Helm chart being installed as a string that is a base64 encoding of the package Helm chart `.tgz` compressed archive. This is done because we are pulling from a private registry, which requires RKE2's Helm controller to have a `ConfigMap` and `Secret` for the CA and credentials, which we cannot create until after the cluster is up. We can pre-embed these like so:

```sh
helm pull oci://registry.ranchercarbide.dev/charts/metallb --version "0.15.3"
helm pull oci://registry.suse.com/edge/charts/endpoint-copier-operator --version "~304.0.1"
metallb="$(base64 metallb-*.tgz)" yq -i '.spec.chartContent = strenv(metallb)' metallb.yaml
eco="$(base64 endpoint-copier-operator-*.tgz)" yq -i '.spec.chartContent = strenv(eco)' endpoint-copier-operator.yaml
```

To add the required container images to our private registry:

```sh
hauler store add image registry.ranchercarbide.dev/hauler/apps-metallb-manifest.yaml:0.15.3 --store tmp-store
hauler store extract registry.ranchercarbide.dev/hauler/apps-metallb-manifest.yaml:0.15.3 --store tmp-store
ECO_IMAGE=$(tar xOf endpoint-copier-operator-304.0.1+up0.3.0.tgz endpoint-copier-operator/values.yaml | 
  yq '.image | (.repository, .tag)' | 
  sed -z 's/\n/:/') yq -i '.spec.images += {"name": strenv(ECO_IMAGE)}' apps-metallb-manifest.yaml
hauler store sync --filename apps-metallb-manifest.yaml --platform linux/amd64
hauler store copy registry://registry.lab.internal:5000
rm -rf store
rm -f apps-metallb-manifest.yaml
```

Finally, the manifest for the VIP itself:

`/var/lib/rancher/rke2/server/manifests/kubernetes-vip.yaml`
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: api-ip
  namespace: metallb-system
spec:
  addresses:
    - 192.168.3.10/32
  avoidBuggyIPs: true
  serviceAllocation:
    namespaces:
      - default
    serviceSelectors:
      - matchExpressions:
          - key: serviceType
            operator: In
            values:
              - kubernetes-vip
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: api-ip-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - api-ip
---
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-vip
  namespace: default
  labels:
    serviceType: kubernetes-vip
spec:
  ipFamilyPolicy: SingleStack
  ipFamilies:
    - IPv4
  ports:
    - name: rke2-api
      port: 9345
      protocol: TCP
      targetPort: 9345
    - name: k8s-api
      port: 6443
      protocol: TCP
      targetPort: 6443
  type: LoadBalancer
```

Finally, in order for Cilium to act as a gateway provider, we need to pre-install the Gateway API CRDs, which Cilium will not do for you:

```sh
sudo curl -fsLS https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/experimental-install.yaml \
  -o /var/lib/rancher/rke2/server/manifests/gateway-api.yaml
```

Note again that there are *many* ways to accomplish this same task. This is simply an example of one way to do it. It is both a blessing and a curse of the SUSE and Rancher ethos that all components are interchangeable and highly configurable, preventing vendor lock-in and allowing use on just about any hardware and/or infrastructure provider, but also forcing you to make decisions.

### Installation

The following repo file for `zypper` is created to grab the RKE2 rpms:

`/etc/zypp/repos.d/rancher-rke2.repo`
```ini
[rancher-rke2-common-stable]
name=Rancher RKE2 Common (stable)
baseurl=https://rpm.rancher.io/rke2/stable/common/slemicro/noarch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://rpm.rancher.io/public.key
[rancher-rke2-1.35-stable]
name=Rancher RKE2 1.35 (stable)
baseurl=https://rpm.rancher.io/rke2/stable/1.35/slemicro/x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://rpm.rancher.io/public.key
```

Then RKE2 can be installed and started by running:

```sh
transactional-update pkg in rke2-selinux rke2-server
systemctl reboot
```

Alternatively, the hosted install script will do the same for you:

```sh
curl -fsLS https://get.rke2.io | sudo INSTALL_RKE2_VERSION="v1.35.8+rke2r1" INSTALL_RKE2_METHOD=rpm bash -
```

It is important to use the rpm method as otherwise SELinux will not be configured correctly to run RKE2 in Enforcing mode.

## Rancher

At this point, installing Rancher itself is pretty simple. Acquire the kubeconfig for the RKE2 default admin at `/etc/rancher/rke2/rke2.yaml`. First, create required secrets for the server certificate and private CA:

```sh
kubectl create secret tls tls-rancher-ingress \
  --cert=rancher.crt \
  --key=rancher.key \
  --namespace cattle-system
kubectl create secret generic tls-ca \
  --from-file=cacerts.pem=ca.crt
```

We also need an auth secret and CA for the Helm controller to use our private registry:

```sh
kubectl create configmap homelab-ca \
  --namespace kube-system \
  --from-literal="ca.crt"="$(cat ca.crt)"
kubectl create secret docker-registry homelab-registry \
  --namespace kube-system \
  --docker-email="noreply@home.internal" \
  --docker-password="$REG_PASSWORD" \
  --docker-server="registry.home.internal:5000" \
  --docker-username="$REG_USER"
```

Then install Rancher, along with its `Gateway` and `HTTPRoute`:

```sh
kubectl apply -f -<<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: rancher
  namespace: cattle-system
  annotations:
    cert-manager.io/cluster-issuer: ca-issuer
spec:
  gatewayClassName: cilium
  listeners:
  - name: https-rancher
    protocol: HTTPS
    port: 443
    hostname: "rancher.home.internal"
    tls:
      certificateRefs:
      - kind: Secret
        name: tls-rancher-ingress
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rancher
  namespace: cattle-system
spec:
  parentRefs:
  - name: rancher
  hostnames:
  - "rancher.home.internal"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: rancher
      port: 80
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ingress-ip
  namespace: metallb-system
spec:
  addresses:
  - 192.168.3.3/32
  avoidBuggyIPs: true
  serviceAllocation:
    namespaces:
    - cattle-system
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ingress-ip-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - ingress-ip
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: rancher
  namespace: kube-system
spec:
  chart: oci://registry.lab.internal:5000/charts/rancher
  dockerRegistrySecret: 
    name: homelab-registry
  failurePolicy: reinstall
  repoCAConfigMap:
    name: homelab-ca
  failurePolicy: reinstall
  targetNamespace: cattle-system
  valuesContent: |-
    hostname: rancher.home.internal
    privateCA: true
    ingress:
      enabled: false
      tls:
        source: secret
  version: 2.14.5
EOF
```

This uses the built-in Helm controller for RKE2 rather than the Helm CLI. No admin password was pre-configured, so Rancher will create a bootstrap password that must be changed on first login. This can be retrieved by running:

```sh
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
```

This is also printed out by the Helm controller pod when the Helm install job is run, but it will not show on screen. It can be retrieved from the logs:

```sh
kubectl logs -n kube-system jobs/helm-install-rancher
```

Read more about the RKE2 Helm controller at [Add-ons > Helm](https://docs.rke2.io/add-ons/helm).

## Keycloak SSO

Login to Rancher as the built-in local admin. Then follow the instructions at [Configure Keycloak (OIDC)](https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/authentication-permissions-and-global-configuration/authentication-config/configure-keycloak-oidc) to be able to use Keycloak as an IDP for SSO.

# Rancher Virtualization Management

To import your Harvester cluster into Rancher to be managed by it, following the instructions at [Rancher Integration](https://docs.harvesterhci.io/v1.8/rancher/rancher-integration). Harvester Government (*not* community) is otherwise compliant with its own DISA STIG out-of-the-box, short of only providing a single break-glass admin user locally. Integration with Rancher is what allows for SSO and multi-user RBAC, making it now fully compliant.

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

# NFS CSI Driver

See [Advanced > Third Party Storage Support](https://docs.harvesterhci.io/v1.8/advanced/csidriver/).

First, we need to stage the Helm chart and container images:

```sh
helm repo add csi-driver-nfs https://kubernetes-csi.github.io/csi-driver-nfs
helm pull csi-driver-nfs/csi-driver-nfs --version 4.13.4
helm push csi-driver-nfs-4.13.4.tgz oci://registry.lab.internal:5000/charts
hauler store add image registry.k8s.io/sig-storage/nfsplugin:v4.13.4
hauler store add image registry.ranchercarbide.dev/rancher/mirrored-sig-storage-csi-provisioner:v6.3.0
hauler store add image registry.ranchercarbide.dev/rancher/mirrored-sig-storage-csi-resizer:v2.2.1
hauler store add image registry.ranchercarbide.dev/rancher/mirrored-sig-storage-csi-snapshotter:v8.6.0
hauler store add image registry.ranchercarbide.dev/rancher/mirrored-sig-storage-livenessprobe:v2.19.0
hauler store add image registry.ranchercarbide.dev/rancher/mirrored-sig-storage-csi-node-driver-registrar:v2.17.0
hauler store add image registry.ranchercarbide.dev/rancher/mirrored-sig-storage-snapshot-controller:v8.4.0
hauler store copy registry://registry.lab.internal:5000
rm -rf store
```

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
  name: homelab-harvester
  namespace: fleet-default
spec:
  repo: git@github.com:acostahome/harvester-example.git
  branch: main
  clientSecretName: ssh-auth-github
  paths:
    - /manifests/harvester/images
  targets:
    - name: harvester
      clusterGroup: homelab-harvester
EOF
```

This targets the cluster group we created earlier.

Currently, the attempt to use Fleet to manage Harvester workloads fails from this private Git server, complaining of a host key mismatch. Rather than figuring out how to fix that, for now, we can simply install the Helm chart by normal means.

First, ensure you are using the correct kubeconfig for the Harvester cluster, *not* Rancher.

```sh
cat <<EOF | helm upgrade csi-driver-nfs oci://registry.lab.internal:5000/charts/csi-driver-nfs --namespace kube-system --version 4.13.4 --values -
controller:
  replicas: 2
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels:
              app: csi-nfs-controller
image:
  baseRepo: registry.lab.internal:5000
  nfs:
    repository: registry.lab.internal:5000/sig-storage/nfsplugin
    tag: v4.13.4
  csiProvisioner:
    repository: /rancher/mirrored-sig-storage-csi-provisioner
    tag: v6.3.0
  csiResizer:
    repository: /rancher/mirrored-sig-storage-csi-resizer
    tag: v2.2.1
  csiSnapshotter:
    repository: /rancher/mirrored-sig-storage-csi-snapshotter
    tag: v8.6.0
  livenessProbe:
    repository: /rancher/mirrored-sig-storage-livenessprobe
    tag: v2.19.0
  nodeDriverRegistrar:
    repository: /rancher/mirrored-sig-storage-csi-node-driver-registrar
    tag: v2.17.0
  externalSnapshotter:
    repository: /rancher/mirrored-sig-storage-snapshot-controller
    tag: v8.4.0
storageClasses:
  - name: nfs-delete
    parameters:
      server: nas.lab.internal
      share: /mnt/shared/data
    reclaimPolicy: Delete
    volumeBindingMode: Immediate
    mountOptions:
      - nfsvers=4.1
  - name: nfs-retain
    parameters:
      server: nas.lab.internal
      share: /mnt/shared/data
    reclaimPolicy: Retain
    volumeBindingMode: Immediate
    mountOptions:
      - nfsvers=4.1
EOF
```

# Conclusion

At this point, we have bare metal RKE2, Rancher, and Harvester all running in a fully-hardened configuration.