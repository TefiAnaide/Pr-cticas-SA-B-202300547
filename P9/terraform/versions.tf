terraform {
  # use_lockfile (bloqueo nativo en S3, sin DynamoDB) es GA desde 1.11.
  required_version = ">= 1.11.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # Estado REMOTO con bloqueo (Practica 9, seccion 3.2). El bucket vive en
  # MinIO (P9/minio/docker-compose.yml), un contenedor FUERA del cluster: si
  # el cluster se destruye, el estado sobrevive. use_lockfile crea
  # "<key>.tflock" con escritura condicional (If-None-Match): dos
  # "terraform apply" simultaneos -> el segundo falla con "state locked".
  #
  # Sin credenciales aqui: se leen de AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY,
  # que P9/scripts/lib.sh exporta desde ~/.sa-p9/minio.env (fuera del repo).
  backend "s3" {
    bucket = "sa-p9-tfstate"
    key    = "p9/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "http://localhost:9100"
    }
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true

    use_lockfile = true
  }
}

provider "kind" {}

# Los providers de Kubernetes/Helm se configuran con las salidas del
# cluster que se crea en ESTE MISMO apply — no dependen de ningun
# kubeconfig previo, por eso el bootstrap funciona en una maquina limpia.
provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}
