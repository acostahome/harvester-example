terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = ">= 0.6"
    }
  }
}

provider "harvester" {
  kubeconfig  = "~/.kube/config"
  kubecontext = "homelab-harvester"
}

# IPPool for Ingress/API load balancers
resource "harvester_ippool" "rancher" {
  name = "rancher"

  range {
    end     = "192.168.3.30"
    gateway = "192.168.3.1"
    start   = "192.168.3.30"
    subnet  = "192.168.3.30/24"
  }

  selector {
    priority = 1024
    scope {
      guest_cluster = "rancher"
      namespace     = "rancher"
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
  network_name = "harvester-public/vmnet1"
  num_vms      = 3
  user_data    = file("${path.module}/files/cloud-config.yaml")
  vm_cpus      = 4
  vm_image     = data.harvester_image.rocky9.id
  vm_name      = "rancher-cp"
  vm_namespace = "rancher"
  vm_ram       = "8Gi"

  mac_address = [
    "52:54:00:12:34:a1",
    "52:54:00:12:34:a2",
    "52:54:00:12:34:a3"
  ]
}

output "primary_ip" {
  value = module.cp.primary_ip
}