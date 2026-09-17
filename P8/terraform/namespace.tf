# Namespace, ResourceQuota y LimitRange de la plataforma. Antes (Practica 5)
# esto vivia como templates del chart padre sa-p5 (templates/resourcequota.yaml,
# templates/limitrange.yaml); la Practica 8 exige que la infraestructura del
# clúster (namespace, cuotas, límites, RBAC) se declare con Terraform y no se
# cree manualmente ni via Helm — por eso se movió aquí y se sacó del chart.

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "sa-p8"
    }
  }
}

# Mismos valores que P5/charts/sa-p5/values.yaml (resourceQuota.hard) —
# medidos en minikube con el ambiente dev, con margen para escalar durante
# pruebas sin dejar de poder demostrar un rechazo real por cuota excedida.
resource "kubernetes_resource_quota" "app" {
  metadata {
    name      = "sa-p8-quota"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"                 = "1500m"
      "requests.memory"              = "1536Mi"
      "limits.cpu"                   = "3000m"
      "limits.memory"                = "3Gi"
      "pods"                         = "30"
      "persistentvolumeclaims"       = "5"
    }
  }
}

# Mismos valores que P5/charts/sa-p5/values.yaml (limitRange) — cinturon de
# seguridad para cualquier container que no declare requests/limits propios.
resource "kubernetes_limit_range" "app" {
  metadata {
    name      = "sa-p8-limits"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "200m"
        memory = "256Mi"
      }
      default_request = {
        cpu    = "50m"
        memory = "64Mi"
      }
      max = {
        cpu    = "500m"
        memory = "512Mi"
      }
      min = {
        cpu    = "10m"
        memory = "16Mi"
      }
    }
  }
}
