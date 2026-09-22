terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = ">= 1.7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2"
    }
  }
}

provider "harvester" {
  kubeconfig  = "~/homelab-harvester.yaml"
  kubecontext = "local"
}

provider "kubernetes" {
  config_path    = "~/homelab-harvester.yaml"
  config_context = "local"
}

data "harvester_image" "rocky9" {
  display_name = "rocky-9-genericcloud-base.latest.x86_64.qcow2"
  namespace    = "harvester-public"
}

resource "kubernetes_namespace_v1" "vm_test" {
  metadata {
    name = "vm-test"
  }
}

module "cp" {
  source = "../.."

  network_data = file("${path.module}/files/network-config.yaml")
  network_name = "harvester-public/vmnet"
  num_vms      = 1
  user_data    = file("${path.module}/files/cloud-config.yaml")
  vm_cpus      = 1
  vm_image     = data.harvester_image.rocky9.id
  vm_name      = "rocky-test"
  vm_namespace = "vm-test"
  vm_ram       = "2Gi"
}

output "primary_ip" {
  value = module.cp.primary_ip
}