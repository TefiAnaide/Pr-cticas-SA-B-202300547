terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

# Sin backend remoto a proposito: esta practica corre contra un clúster
# local (kind) que se recrea en cada corrida de CI/demo, así que no hay
# estado que valga la pena persistir entre corridas. `terraform init
# -backend=false` (usado por la verificación) funciona igual.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context != "" ? var.kube_context : null
}
