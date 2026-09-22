terraform {
  required_version = ">= 0.13"
  required_providers {
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3"
    }
    harvester = {
      source  = "harvester/harvester"
      version = ">= 0.6"
    }
  }
}

provider "harvester" {
  kubeconfig  = "~/.kube/config"
  kubecontext = "homelab"
}

data "harvester_image" "sles16" {
  display_name = "SLES-16.0-Minimal-VM.x86_64-Cloud-QU1.qcow2"
  namespace    = "harvester-public"
}

data "cloudinit_config" "server" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "init.sh"
    content_type = "text/x-shellscript"
    content      = <<-EOF
    #!/bin/sh
    systemctl enable --now qemu-guest-agent
    suseconnect -r INTERNAL-USE-ONLY-01e9-c544
    zypper up -y
    [ -f /var/run/reboot-needed ] && systemctl reboot
    EOF
  }

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = <<-EOF
    #cloud-config
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUV5mYJt2mNSayglG9+ez4W66Cj5PdBfvg5+Mqf+e9G
    EOF
  }
}

module "vm" {
  source = "../.."

  network_data = <<-EOF
  network:
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
      dhcp-identifier: mac
  version: 2
  EOF
  network_name = "harvester-public/vmnet1"
  user_data    = data.cloudinit_config.server.rendered
  vm_cpus      = 4
  vm_image     = data.harvester_image.sles16.id
  vm_name      = "sles16-test"
  vm_namespace = "vms"
  vm_ram       = "8Gi"
}

output "primary_ip" {
  value = module.vm.primary_ip
}