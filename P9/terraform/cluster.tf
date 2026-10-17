# Paso 1 del bootstrap: el cluster. 1 control-plane + N workers para que
# la anti-afinidad reparta las replicas del api-gateway en nodos distintos
# y un drenaje de nodo no deje el servicio en cero.
resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = pathexpand(var.kubeconfig_path)

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
    }

    dynamic "node" {
      for_each = range(var.workers)
      content {
        role = "worker"
      }
    }
  }
}

# StorageClass para datos que SI deben respaldarse. El local-path de kind
# crea por defecto volumenes "hostPath", y el File System Backup de Velero
# NO soporta hostPath (los omite). Con defaultVolumeType=local el mismo
# provisionador crea PVs tipo "local", que kubelet monta dentro de
# /var/lib/kubelet/pods/... y el node-agent de Velero si puede leer.
resource "kubernetes_storage_class_v1" "respaldable" {
  metadata {
    name = "local-respaldable"
    annotations = {
      "defaultVolumeType" = "local"
    }
  }
  storage_provisioner    = "rancher.io/local-path"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = false
}
