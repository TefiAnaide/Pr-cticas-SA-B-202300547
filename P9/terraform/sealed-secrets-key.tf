# Continuidad de los secretos (Practica 9, seccion 3.2).
#
# Los SealedSecrets del repo GitOps se cifraron con la llave del
# controlador del cluster original. Si el cluster nuevo arranca con una
# llave nueva, esos SealedSecrets se vuelven ilegibles. Por eso la llave
# respaldada (P9/scripts/respaldar-llave.sh -> MinIO) se inyecta aqui ANTES
# de que ArgoCD instale el controlador: al arrancar, el controlador
# encuentra un Secret con la etiqueta sealed-secrets-key=active en
# kube-system y la usa en lugar de generar una nueva.
#
# Si el directorio esta vacio (primer arranque de la historia), no se crea
# nada: el controlador genera una llave y bootstrap.sh la respalda al final.

locals {
  sealed_key_dir   = pathexpand(var.sealed_secrets_key_dir)
  sealed_key_names = toset([for f in fileset(local.sealed_key_dir, "*.crt") : trimsuffix(f, ".crt")])
}

resource "kubernetes_secret_v1" "sealed_secrets_key" {
  for_each = local.sealed_key_names

  metadata {
    name      = each.value
    namespace = "kube-system"
    labels = {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    }
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = file("${local.sealed_key_dir}/${each.value}.crt")
    "tls.key" = file("${local.sealed_key_dir}/${each.value}.key")
  }

  depends_on = [kind_cluster.this]
}
