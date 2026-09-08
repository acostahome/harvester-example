variable "cluster_name" {
  default = null
  type    = string
}

variable "cni" {
  default = "cilium"
  type    = string
}

variable "cp_cpu" {
  default = 2
  type    = number
}

variable "cp_memory" {
  default = 4
  type    = number
}

variable "cp_nodes" {
  default = 1
  type    = number
}

variable "cp_root_disk_size" {
  default = 40
  type    = number
}

variable "hvst_cluster_id" {
  default = null
  type    = string
}

variable "hvst_sa_kubeconfig" {
  default = null
  type    = string
}

variable "kubernetes_version" {
  default = null
  type    = string
}

variable "network_name" {
  default = null
  type    = string
}

variable "network_namespace" {
  default = "harvester-public"
  type    = string
}

variable "psa_template" {
  default = "rancher-restricted"
  type    = string
}

variable "rancher_url" {
  default = null
  type    = string
}

variable "rancher_token" {
  default = null
  type    = string
}

variable "registry_password" {
  default = null
  type    = string
}

variable "registry_user" {
  default = null
  type    = string
}

variable "ssh_user" {
  default = null
  type    = string
}

variable "system_default_registry" {
  default = null
  type    = string
}

variable "vmi_name" {
  default = null
  type    = string
}

variable "vmi_namespace" {
  default = "harvester-public"
  type    = string
}

variable "vm_namespace" {
  default = null
  type    = string
}

variable "worker_cpu" {
  default = 4
  type    = number
}

variable "worker_memory" {
  default = 8
  type    = number
}

variable "worker_nodes" {
  default = 0
  type    = number
}

variable "worker_root_disk_size" {
  default = 40
  type    = number
}