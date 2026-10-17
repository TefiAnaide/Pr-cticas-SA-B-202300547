# Namespace, cuotas, limites y RBAC de la plataforma — mismo contenido que
# P8/terraform/namespace.tf y rbac.tf (ver esos archivos para la
# justificacion de cada valor). Se repiten aqui porque en la Practica 9 el
# cluster lo crea este mismo Terraform, y estos recursos deben existir
# ANTES de que ArgoCD despliegue la aplicacion (los charts usan
# serviceAccount.create=false y CreateNamespace=false).

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "sa-p8"
    }
  }
}

resource "kubernetes_resource_quota" "app" {
  metadata {
    name      = "sa-p8-quota"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  # Practica 10: cuota ampliada (era 1500m / 1536Mi / 3000m / 3Gi). Medido el
  # 2026-10-17 con la release v0.3.1: con la cuota anterior un rolling update
  # NO cabia. Durante el despliegue conviven pods viejos y nuevos (maxSurge
  # 25% = 1 pod extra por servicio) y limits.cpu llego a 2980m/3000m:
  # "exceeded quota" bloqueo a productos, reportes y hasta a los CronJobs.
  # Ademas el SDK de OpenTelemetry sube la memoria del api-gateway de 96Mi a
  # 256Mi y la de los servicios Python de 128Mi a 192Mi (values-p10.yaml).
  # Margen: la carga estable mas un servicio completo en surge.
  spec {
    hard = {
      "requests.cpu"           = "2000m"
      "requests.memory"        = "2Gi"
      "limits.cpu"             = "4000m"
      "limits.memory"          = "4Gi"
      "pods"                   = "30"
      "persistentvolumeclaims" = "5"
    }
  }
}

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

resource "kubernetes_service_account" "service" {
  for_each = toset(var.services)

  metadata {
    name      = each.value
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  automount_service_account_token = false
}

resource "kubernetes_role" "service" {
  for_each = toset(var.services)

  metadata {
    name      = each.value
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = [each.value]
    verbs          = ["get"]
  }
}

resource "kubernetes_role_binding" "service" {
  for_each = toset(var.services)

  metadata {
    name      = each.value
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.service[each.value].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.service[each.value].metadata[0].name
    namespace = kubernetes_namespace.app.metadata[0].name
  }
}
