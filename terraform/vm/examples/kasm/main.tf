terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = ">= 0.6"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0"
    }
  }
}

provider "harvester" {
  kubeconfig  = "~/.kube/config"
  kubecontext = "homelab-harvester"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "homelab-harvester"
}

locals {
  cluster_name      = "kasm"
  image_name        = "noble-server-cloudimg-amd64.img"
  image_server      = "http://192.168.3.138:8080"
  ip_pool_cidr      = "192.168.3.30/24"
  ip_pool_cidr_host = 30
  network_name      = "harvester-public/vmnet1"
}

resource "kubernetes_namespace_v1" "kasm" {
  metadata {
    name = local.cluster_name
  }

  # Internal Rancher adds cattle.io annotations for tracking
  lifecycle {
    ignore_changes = [metadata["annotations"]]
  }
}

# IPPool for Ingress/API load balancers
resource "harvester_ippool" "rancher" {
  name = local.cluster_name

  range {
    end     = cidrhost(local.ip_pool_cidr, local.ip_pool_cidr_host)
    gateway = cidrhost(local.ip_pool_cidr, 1)
    start   = cidrhost(local.ip_pool_cidr, local.ip_pool_cidr_host)
    subnet  = local.ip_pool_cidr
  }

  selector {
    priority = 1024
    scope {
      guest_cluster = local.cluster_name
      namespace     = local.cluster_name
    }
  }
}

data "harvester_image" "rocky9" {
  display_name = "Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  namespace    = "harvester-public"
}

module "cp" {
  source = "../.."

  network_data = file("${path.module}/files/network-config.yaml")
  network_name = local.network_name
  num_vms      = 3
  user_data    = file("${path.module}/files/cloud-config.yaml")
  vm_cpus      = 4
  vm_image     = data.harvester_image.rocky9.id
  vm_name      = "${local.cluster_name}-cp"
  vm_namespace = local.cluster_name
  vm_ram       = "8Gi"

  mac_address = [
    "52:54:00:12:34:a1",
    "52:54:00:12:34:a2",
    "52:54:00:12:34:a3"
  ]
}

output "cluster_ips" {
  value = module.cp.primary_ip
}

# Kasm Docker agent
data "harvester_image" "ubuntu24" {
  display_name = local.image_name
  namespace    = "harvester-public"
}

resource "kubernetes_namespace_v1" "kasm_agent" {
  metadata {
    name = "${local.cluster_name}-agent"
  }

  lifecycle {
    ignore_changes = [metadata["annotations"]]
  }
}

module "kasm_agent" {
  source = "../.."

  network_data   = file("${path.module}/files/kasmagent-network-config.yaml")
  network_name   = local.network_name
  num_vms        = 1
  root_disk_size = "100Gi"
  user_data      = file("${path.module}/files/kasmagent-cloud-config.yaml")
  vm_cpus        = 2
  vm_image       = data.harvester_image.ubuntu24.id
  vm_name        = "${local.cluster_name}-agent"
  vm_namespace   = kubernetes_namespace_v1.kasm_agent.metadata[0].name
  vm_ram         = "8Gi"

  mac_address = ["52:54:00:12:35:a1"]
}

output "agent_ip" {
  value = module.kasm_agent.primary_ip[0]
}

# Kasm autoscaling
data "harvester_clusternetwork" "vmnet" {
  name = "vmnet"
}

resource "kubernetes_namespace_v1" "kasm_autoscale" {
  metadata {
    name = "${local.cluster_name}-autoscale"
  }

  lifecycle {
    ignore_changes = [metadata["annotations"]]
  }
}

resource "harvester_network" "kasm_autoscale" {
  name      = "${local.cluster_name}-autoscale"
  namespace = kubernetes_namespace_v1.kasm_autoscale.metadata[0].name

  vlan_id = 0

  cluster_network_name = data.harvester_clusternetwork.vmnet.name

  lifecycle {
    ignore_changes = [labels]
  }
}

resource "harvester_image" "ubuntu24" {
  display_name = local.image_name
  name         = "ubuntu24"
  namespace    = kubernetes_namespace_v1.kasm_autoscale.metadata[0].name
  source_type  = "download"
  url          = "${local.image_server}/${local.image_name}"
}
