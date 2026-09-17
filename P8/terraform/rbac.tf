# RBAC de minimo privilegio, uno por microservicio: cada ServiceAccount solo
# puede leer (get) SU PROPIO ConfigMap, nada mas — mismo patron que antes
# vivia en templates/role.yaml y templates/rolebinding.yaml de cada subchart
# de Helm (api-gateway, auth-service, etc.), migrado a Terraform. Los charts
# de Helm ya no crean estas ServiceAccounts (serviceAccount.create=false en
# values-terraform.yaml del repo GitOps) — Terraform es ahora el único dueño.
#
# Los Secrets deliberadamente NO son legibles via RBAC (ni siquiera de
# lectura propia): siguen siendo accesibles unicamente como variables de
# entorno inyectadas por el pod spec, nunca por llamada a la API.

resource "kubernetes_service_account" "service" {
  for_each = toset(var.services)

  metadata {
    name      = each.value
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  # Ninguno de los 6 microservicios llama a la API de Kubernetes desde su
  # codigo — no hay razon para que el pod cargue un token que nunca usa.
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
