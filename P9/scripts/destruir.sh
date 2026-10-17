#!/usr/bin/env bash
# Simula la PERDIDA TOTAL del entorno para la prueba de recuperacion
# cronometrada. No es un "terraform destroy" ordenado: el cluster se borra
# por fuera de Terraform (como si la maquina/nube desapareciera), y se
# borran tambien las copias locales de la llave de Sealed Secrets y del
# kubeconfig, para que la reconstruccion dependa SOLO de Git + MinIO.
#
# Queda en pie, a proposito: el almacenamiento externo (MinIO), que es
# justamente lo que el plan de DR asume que sobrevive.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cargar_credenciales
LOG="$EVIDENCIAS/destruccion-$(date +%Y%m%d-%H%M%S).log"

# Salvaguarda: no borrar la copia local de la llave si NO esta en MinIO.
if ! s3 s3 ls "s3://$BUCKET_LLAVES/sealed-secrets/" | grep -q '\.key'; then
  falla "la llave de Sealed Secrets no esta respaldada en MinIO; corra scripts/respaldar-llave.sh antes"
fi

log "Estado previo:"
run kubectl get applications -n argocd
run velero backup get
psql_pg productos_db "SELECT etapa, creado FROM dr_marcas ORDER BY id" 2>&1 | tee -a "$LOG"

echo "$(date +%s) $(ts)" > "$SA_P9_HOME/ultima-destruccion"
marca "DESTRUCCION_INICIO"
run kind delete cluster --name "$CLUSTER"
rm -rf "$LLAVES_DIR" "$KUBECONFIG"
marca "DESTRUCCION_FIN"
log "Cluster '$CLUSTER', llave local y kubeconfig eliminados. Para reconstruir: ./P9/bootstrap.sh"
