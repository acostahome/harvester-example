locals {
  cluster_name            = var.cluster_name
  cni                     = var.cni
  cp_cpu                  = var.cp_cpu
  cp_memory               = var.cp_memory
  cp_nodes                = var.cp_nodes
  cp_root_disk_size       = var.cp_root_disk_size
  hvst_cluster_id         = var.hvst_cluster_id
  hvst_sa_kubeconfig      = var.hvst_sa_kubeconfig
  kubernetes_version      = var.kubernetes_version
  network_name            = var.network_name
  network_namespace       = var.network_namespace
  psa_template            = var.psa_template
  registry_password       = var.registry_password
  registry_user           = var.registry_user
  ssh_user                = var.ssh_user
  system_default_registry = var.system_default_registry
  vmi_name                = var.vmi_name
  vmi_namespace           = var.vmi_namespace
  vm_namespace            = var.vm_namespace
  worker_cpu              = var.worker_cpu
  worker_memory           = var.worker_memory
  worker_nodes            = var.worker_nodes
  worker_root_disk_size   = var.worker_root_disk_size
}

data "rancher2_cluster_v2" "harvester" {
  name = local.hvst_cluster_id
}

resource "rancher2_cloud_credential" "harvester" {
  name = local.cluster_name

  harvester_credential_config {
    cluster_id         = data.rancher2_cluster_v2.harvester.cluster_v1_id
    cluster_type       = "imported"
    kubeconfig_content = data.rancher2_cluster_v2.harvester.kube_config
  }
}

resource "rancher2_secret_v2" "registryconfig-auth" {
  cluster_id = "local"
  name       = "registryconfig-auth-${local.cluster_name}"
  namespace  = "fleet-default"
  type       = "kubernetes.io/basic-auth"

  data = {
    password = local.registry_password
    username = local.registry_user
  }
}

resource "rancher2_machine_config_v2" "cp" {
  generate_name = "${local.cluster_name}-cp"

  harvester_config {
    cpu_count   = local.cp_cpu
    memory_size = local.cp_memory
    disk_info = jsonencode({
      disks = [{
        imageName = "${local.vmi_namespace}/${local.vmi_name}"
        size      = local.cp_root_disk_size
        bootOrder = 1
      }]
    })
    network_info = jsonencode({
      interfaces = [{
        networkName = "${local.network_namespace}/${local.network_name}"
      }]
    })
    ssh_user     = local.ssh_user
    user_data    = file("${path.module}/files/cloud-config.yaml")
    vm_namespace = local.vm_namespace
  }
}

resource "rancher2_machine_config_v2" "worker" {
  count = local.worker_nodes > 0 ? 1 : 0

  generate_name = "${local.cluster_name}-worker"

  harvester_config {
    cpu_count   = local.cp_cpu
    memory_size = local.cp_memory
    disk_info = jsonencode({
      disks = [{
        imageName = "${local.vmi_namespace}/${local.vmi_name}"
        size      = local.cp_root_disk_size
        bootOrder = 1
      }]
    })
    network_info = jsonencode({
      interfaces = [{
        networkName = "${local.network_namespace}/${local.network_name}"
      }]
    })
    ssh_user     = local.ssh_user
    user_data    = file("${path.module}/files/cloud-config.yaml")
    vm_namespace = local.vm_namespace
  }
}

resource "rancher2_cluster_v2" "demo" {
  name = local.cluster_name

  cloud_credential_secret_name                               = rancher2_cloud_credential.harvester.id
  default_pod_security_admission_configuration_template_name = local.psa_template
  enable_network_policy                                      = false
  kubernetes_version                                         = local.kubernetes_version

  rke_config {
    additional_manifest = <<-EOF
    apiVersion: helm.cattle.io/v1
    kind: HelmChartConfig
    metadata:
      name: rke2-traefik
      namespace: kube-system
    spec:
      valuesContent: |-
        service:
          annotations:
            cloudprovider.harvesterhci.io/ipam: pool
          spec:
            type: LoadBalancer
    EOF
    chart_values = yamlencode({
      harvester-cloud-provider = {
        cloudConfigPath = "/var/lib/rancher/rke2/etc/config-files/cloud-provider-config"
        global = {
          cattle = {
            clusterName = local.cluster_name
          }
        }
      }
      rke2-cilium = {
        operator = {
          replicas = local.cp_nodes + local.worker_nodes > 1 ? 2 : 1
        }
      }
    })
    machine_global_config = yamlencode({
      cni                 = local.cni
      etcd-expose-metrics = false
      ingress-controller  = "traefik"
      kube-apiserver-arg = [
        "admission-control-config-file=/etc/rancher/rke2/config/rancher-psact.yaml"
      ]
    })

    machine_pools {
      name               = "cp"
      control_plane_role = true
      etcd_role          = true
      worker_role        = true
      quantity           = local.cp_nodes

      machine_config {
        kind = rancher2_machine_config_v2.cp.kind
        name = rancher2_machine_config_v2.cp.name
      }
    }

    dynamic "machine_pools" {
      for_each = local.worker_nodes > 0 ? [1] : []
      content {
        name               = "worker"
        control_plane_role = false
        etcd_role          = false
        worker_role        = true
        quantity           = local.worker_nodes

        machine_config {
          kind = rancher2_machine_config_v2.worker[0].kind
          name = rancher2_machine_config_v2.worker[0].name
        }
      }
    }

    machine_selector_config {
      config = yamlencode({
        cloud-provider-config = local.hvst_sa_kubeconfig
        cloud-provider-name   = "harvester"
      })
    }

    registries {
      configs {
        hostname                = local.system_default_registry
        auth_config_secret_name = "registryconfig-auth-${local.cluster_name}"
      }
      mirrors {
        hostname = "docker.io"
        endpoints = ["registry.lab.internal:5000"]
      }
      mirrors {
        hostname = "registry.rancher.com"
        endpoints = ["registry.lab.internal:5000"]
      }
      mirrors {
        hostname = "registry.suse.com"
        endpoints = ["registry.lab.internal:5000"]
      }
    }
  }

  # Rancher will create a secret in fleet-default of local cluster and update
  # the cloud-provider-config to reference that instead of the file read
  lifecycle {
    ignore_changes = [rke_config[0].machine_selector_config[0].config]
  }
}

output "kubeconfig" {
  sensitive = true
  value     = rancher2_cluster_v2.demo.kube_config
}