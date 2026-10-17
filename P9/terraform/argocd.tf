# Pasos 2 y 3 del bootstrap: ArgoCD y la aplicacion raiz (app-of-apps).
# Desde aqui, TODO lo demas (Sealed Secrets, Argo Rollouts, Kyverno y sus
# politicas, Velero y su Schedule, y la plataforma de microservicios) lo
# levanta ArgoCD leyendo la carpeta apps/ del repositorio GitOps, en el
# orden de sus sync-waves. Terraform no conoce ninguna de esas piezas.

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.9.2"
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [file("${path.module}/values/argocd.yaml")]

  depends_on = [kind_cluster.this]
}

resource "helm_release" "root_app" {
  name       = "sa-p9-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.5"
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      "sa-p9-root" = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.gitops_repo
          targetRevision = var.gitops_revision
          path           = "apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  # La llave de Sealed Secrets, el namespace/RBAC y el StorageClass deben
  # existir antes de que la raiz empiece a crear aplicaciones hijas.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.sealed_secrets_key,
    kubernetes_namespace.app,
    kubernetes_resource_quota.app,
    kubernetes_limit_range.app,
    kubernetes_role_binding.service,
    kubernetes_storage_class_v1.respaldable,
  ]
}
