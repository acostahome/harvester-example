terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = ">= 0.6"
    }
  }
}

# provider "harvester" {
#   kubeconfig  = "$HOME/.kube/config"
#   kubecontext = "homelab"
# }