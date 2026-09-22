locals {
  mac_address    = var.mac_address
  network_data   = var.network_data
  network_name   = var.network_name
  num_vms        = var.num_vms
  root_disk_size = var.root_disk_size
  run_strategy   = var.run_strategy
  user_data      = var.user_data
  vm_cpus        = var.vm_cpus
  vm_image       = var.vm_image
  vm_name        = var.vm_name
  vm_namespace   = var.vm_namespace
  vm_ram         = var.vm_ram
}

resource "harvester_cloudinit_secret" "cloud-config" {
  name      = "cloud-config-${local.vm_name}"
  namespace = local.vm_namespace

  user_data    = local.user_data
  network_data = local.network_data
}

resource "harvester_virtualmachine" "vm" {
  count = local.num_vms

  name                 = "${local.vm_name}-${count.index}"
  namespace            = local.vm_namespace
  restart_after_update = true

  cpu    = local.vm_cpus
  memory = local.vm_ram

  efi = true

  run_strategy = local.run_strategy
  hostname     = "${local.vm_name}-${count.index}"

  network_interface {
    mac_address    = local.mac_address == null ? null : local.mac_address[count.index]
    name           = "nic-0"
    network_name   = local.network_name
    wait_for_lease = true
  }

  disk {
    name       = "rootdisk"
    type       = "disk"
    size       = local.root_disk_size
    bus        = "virtio"
    boot_order = 1

    image       = local.vm_image
    auto_delete = true
  }

  cloudinit {
    user_data_secret_name    = harvester_cloudinit_secret.cloud-config.name
    network_data_secret_name = harvester_cloudinit_secret.cloud-config.name
  }

  # CSI provider may attach new disks at runtime
  lifecycle {
    ignore_changes = [disk]
  }
}

output "primary_ip" {
  value = harvester_virtualmachine.vm[*].network_interface[0].ip_address
}