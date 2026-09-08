terraform {
  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = ">= 13.1"
    }
    harvester = {
      source  = "harvester/harvester"
      version = ">= 0.6"
    }
  }
}

provider "harvester" {
  kubeconfig = "/Users/adam/homelab-harvester.yaml"
}

locals {
  hvst_cluster_id = "c-h4cj9"
  name            = "demo-cluster"
  namespace       = "demo-cluster"
  vmi_name        = "leap-16"
}

# IPPool for Ingress/API load balancers
resource "harvester_ippool" "ingress" {
  name = "${local.name}-ingress"

  range {
    end     = "192.168.3.30"
    gateway = "192.168.3.1"
    start   = "192.168.3.30"
    subnet  = "192.168.3.30/24"
  }

  selector {
    network  = "harvester-public/vmnet"
    priority = 512
    scope {
      guest_cluster = local.name
      namespace     = local.namespace
    }
  }
}

module "cluster" {
  source = "../.."

  cluster_name            = local.name
  cp_nodes                = 3
  hvst_cluster_id         = local.hvst_cluster_id
  hvst_sa_kubeconfig      = file("${path.module}/files/demo-cluster-kubeconfig")
  kubernetes_version      = "v1.35.7+rke2r1"
  network_name            = "vmnet"
  registry_password       = "Rancher!234"
  registry_user           = "rancher"
  ssh_user                = "sles"
  system_default_registry = "registry.lab.internal:5000"
  vm_namespace            = local.namespace
  vmi_name                = local.vmi_name
}

output "kubeconfig" {
  sensitive = true
  value     = module.cluster.kubeconfig
}