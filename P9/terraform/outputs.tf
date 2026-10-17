output "kubeconfig_path" {
  description = "kubeconfig del cluster (export KUBECONFIG=...)."
  value       = pathexpand(var.kubeconfig_path)
}

output "cluster_endpoint" {
  value = kind_cluster.this.endpoint
}

output "sealed_secrets_keys_restauradas" {
  description = "Llaves de Sealed Secrets inyectadas desde el respaldo (vacio = primer arranque, llave nueva)."
  value       = sort(tolist(local.sealed_key_names))
}

output "aplicacion_raiz" {
  value = "sa-p9-root (namespace argocd)"
}
