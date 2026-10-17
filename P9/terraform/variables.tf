variable "cluster_name" {
  description = "Nombre del cluster kind de la Practica 9."
  type        = string
  default     = "sa-p9"
}

variable "node_image" {
  description = "Imagen de nodo de kind, fijada por digest (reproducible)."
  type        = string
  default     = "kindest/node:v1.34.11@sha256:44e222ee2132dab25ff87301682f89eb82c7880ea3a1bf543bfe9708fd08d67d"
}

variable "workers" {
  description = "Nodos worker. Minimo 2: la prueba de perdida de nodo drena uno y el servicio debe seguir respondiendo desde el otro."
  type        = number
  default     = 2
}

variable "kubeconfig_path" {
  description = "Donde escribir el kubeconfig del cluster (fuera del repo)."
  type        = string
  default     = "~/.kube/sa-p9.config"
}

variable "sealed_secrets_key_dir" {
  description = "Directorio (fuera del repo) con la(s) llave(s) de Sealed Secrets respaldadas: <nombre>.crt + <nombre>.key. P9/bootstrap.sh la descarga de MinIO si no existe localmente."
  type        = string
  default     = "~/.sa-p9/sealed-secrets"
}

variable "namespace" {
  description = "Namespace de la plataforma de microservicios (el mismo de la Practica 8)."
  type        = string
  default     = "sa-p8"
}

variable "services" {
  description = "Microservicios de la plataforma — uno por ServiceAccount/Role/RoleBinding."
  type        = list(string)
  default = [
    "api-gateway",
    "auth-service",
    "authz-service",
    "pedidos-service",
    "productos-service",
    "reportes-service",
  ]
}

variable "gitops_repo" {
  description = "Repositorio GitOps (publico) que ArgoCD sincroniza."
  type        = string
  default     = "https://github.com/TefiAnaide/Practicas-SA-GitOps.git"
}

variable "gitops_revision" {
  description = "Rama/tag del repositorio GitOps."
  type        = string
  default     = "main"
}
