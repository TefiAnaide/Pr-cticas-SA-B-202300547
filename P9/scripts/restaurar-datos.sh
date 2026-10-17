#!/usr/bin/env bash
# Restaura el volumen de Postgres desde un respaldo de Velero.
#
#   ./P9/scripts/restaurar-datos.sh <nombre-del-backup>
#
# Lo usan tanto bootstrap.sh (reconstruccion total) como
# prueba-restauracion-datos.sh (perdida de datos): un solo procedimiento,
# probado en los dos escenarios.
#
# Por que se pausa ArgoCD: con selfHeal activo, ArgoCD recrearia el
# StatefulSet de Postgres con un volumen VACIO en cuanto se borra, antes
# de que Velero pueda restaurarlo. Se pausa la raiz (que si no revertiria
# el cambio sobre la hija) y la hija sa-p8, y se reanudan al terminar.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

BACKUP="${1:?uso: restaurar-datos.sh <backup>}"
RESTORE="restaurar-pg-$(date +%Y%m%d-%H%M%S)"

reanudar_argocd() {
  echo "$(ts) Reanudando la sincronizacion automatica de ArgoCD"
  for a in sa-p8 sa-p9-root; do
    kubectl patch application "$a" -n argocd --type merge \
      -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
  done
}
trap reanudar_argocd EXIT

echo "$(ts) Pausando ArgoCD (sa-p9-root y sa-p8)"
for a in sa-p9-root sa-p8; do
  kubectl patch application "$a" -n argocd --type json \
    -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]' >/dev/null 2>&1 || true
done

echo "$(ts) Retirando el Postgres actual (StatefulSet + PVC)"
kubectl delete statefulset postgres -n "$APP_NS" --wait=true --ignore-not-found
kubectl delete pvc data-postgres-0 -n "$APP_NS" --wait=true --ignore-not-found
kubectl wait --for=delete pod/postgres-0 -n "$APP_NS" --timeout=180s 2>/dev/null || true

# Solo los objetos de Postgres: StatefulSet, su PVC, su PV y su pod.
#  - pod: el File System Backup restaura los datos a traves de un init
#    container (restore-wait) que Velero inyecta en el pod restaurado.
#  - persistentvolumes: al procesar el PV, Velero detecta que sus datos
#    vienen del File System Backup, NO lo recrea y limpia spec.volumeName
#    del PVC para que se aprovisione uno nuevo. Sin incluirlo, el PVC queda
#    apuntando al PV borrado y el pod se queda Pending para siempre.
echo "$(ts) velero restore create $RESTORE --from-backup $BACKUP"
velero restore create "$RESTORE" --from-backup "$BACKUP" \
  --include-namespaces "$APP_NS" \
  --include-resources statefulsets,pods,persistentvolumeclaims,persistentvolumes \
  --selector app.kubernetes.io/name=postgresql \
  --wait

FASE=$(kubectl get restores.velero.io "$RESTORE" -n velero -o jsonpath='{.status.phase}')
echo "$(ts) Restore $RESTORE -> $FASE"
velero restore describe "$RESTORE" --details | sed -n '/Phase/,/Restore PVs/p;/Pod Volume Restores/,$p'
[ "$FASE" = "Completed" ] || { echo "Restore no Completed"; exit 1; }

kubectl wait --for=condition=Ready pod/postgres-0 -n "$APP_NS" --timeout=300s || { echo "postgres-0 no quedo Ready"; exit 1; }
echo "$(ts) postgres-0 Ready con los datos restaurados"
