variable "kubeconfig_path" {
  description = "Ruta al kubeconfig del clúster (local: kind; CI: el que genere el runner)."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexto de kubectl a usar. Vacío = el contexto actual."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace donde vive la plataforma de microservicios de la Practica 8."
  type        = string
  default     = "sa-p8"
}

variable "services" {
  description = "Microservicios de la plataforma (Practicas 5-8) — uno por ServiceAccount/Role/RoleBinding."
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
