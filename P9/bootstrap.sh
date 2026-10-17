#!/usr/bin/env bash
# =============================================================================
# PUNTO DE ENTRADA UNICO DEL BOOTSTRAP (Practica 9)
#
#   ./P9/bootstrap.sh
#
# Reconstruye TODO el sistema desde cero, sin pasos manuales intermedios:
#   1. Almacenamiento externo (MinIO) arriba y buckets creados.
#   2. Llave de Sealed Secrets recuperada del respaldo externo.
#   3. Terraform (estado remoto en MinIO): cluster kind + StorageClass +
#      namespace/cuotas/RBAC + llave de Sealed Secrets + ArgoCD + app raiz.
#   4. ArgoCD (app-of-apps, carpeta apps/ del repo GitOps) levanta por olas:
#      sealed-secrets -> argo-rollouts, kyverno -> credenciales de velero ->
#      velero (+Schedule), politicas -> plataforma sa-p8.
#   5. Si existe un respaldo de Velero previo, restaura los datos de Postgres.
#   6. Verifica (apps, secretos descifrados, datos, health) e imprime el RTO.
#
# Idempotente: correrlo sobre un sistema sano no rompe nada.
# Todo queda registrado con marcas de tiempo en P9/evidencias/.
# =============================================================================
set -uo pipefail
source "$(dirname "$0")/scripts/lib.sh"

LOG="$EVIDENCIAS/reconstruccion-$(date +%Y%m%d-%H%M%S).log"
T0=$(date +%s)
marca "INICIO_BOOTSTRAP"
[ -f "$SA_P9_HOME/ultima-destruccion" ] && \
  log "Ultima destruccion registrada: $(cat "$SA_P9_HOME/ultima-destruccion") ($(date -d @"$(cut -d' ' -f1 "$SA_P9_HOME/ultima-destruccion")" '+%F %T'))"

# -----------------------------------------------------------------------------
log "== 0. Herramientas"
for t in docker kind kubectl terraform helm velero aws jq openssl; do
  command -v "$t" >/dev/null || falla "falta la herramienta: $t"
done
terraform version | head -1 | tee -a "$LOG"

# -----------------------------------------------------------------------------
log "== 1. Almacenamiento externo (MinIO, fuera del cluster)"
cargar_credenciales
docker network inspect kind >/dev/null 2>&1 || run docker network create kind
run docker compose -f "$P9_DIR/minio/docker-compose.yml" up -d
esperar 120 "MinIO responde" curl -fs "$MINIO_URL/minio/health/live" || falla "MinIO no arranco"
for b in "$BUCKET_TFSTATE" "$BUCKET_VELERO" "$BUCKET_LLAVES"; do
  s3 s3api head-bucket --bucket "$b" >/dev/null 2>&1 || run s3 s3api create-bucket --bucket "$b"
done
# Versionado del estado: si un apply lo corrompe, se puede volver atras.
s3 s3api put-bucket-versioning --bucket "$BUCKET_TFSTATE" --versioning-configuration Status=Enabled

# -----------------------------------------------------------------------------
log "== 2. Llave de Sealed Secrets"
mkdir -p "$LLAVES_DIR" && chmod 700 "$LLAVES_DIR"
if ls "$LLAVES_DIR"/*.crt >/dev/null 2>&1; then
  log "Llave presente localmente: $(ls "$LLAVES_DIR" | tr '\n' ' ')"
elif s3 s3 ls "s3://$BUCKET_LLAVES/sealed-secrets/" >/dev/null 2>&1; then
  run s3 s3 cp "s3://$BUCKET_LLAVES/sealed-secrets/" "$LLAVES_DIR/" --recursive
  chmod 600 "$LLAVES_DIR"/*
  log "Llave recuperada del almacenamiento externo"
else
  log "AVISO: no hay llave respaldada -> primer arranque, el controlador generara una nueva"
fi

# -----------------------------------------------------------------------------
log "== 3. Terraform: cluster + ArgoCD + aplicacion raiz"
cd "$P9_DIR/terraform" || falla "no existe P9/terraform"
run terraform init -input=false -reconfigure || falla "terraform init"

# Si el cluster fue destruido fuera de Terraform (perdida real, no un
# "terraform destroy"), el estado todavia lista recursos que vivian DENTRO
# del cluster perdido. Refrescarlos contra un API server que ya no existe
# falla, asi que se retiran del estado: la verdad es que ya no existen.
if ! docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1; then
  mapfile -t HUERFANOS < <(terraform state list 2>/dev/null)
  if [ "${#HUERFANOS[@]}" -gt 0 ]; then
    log "Cluster ausente pero el estado lista ${#HUERFANOS[@]} recursos: se retiran del estado"
    run terraform state rm "${HUERFANOS[@]}" || falla "terraform state rm"
  fi
fi
marca "TERRAFORM_APPLY_INICIO"
run terraform apply -input=false -auto-approve || falla "terraform apply"
marca "TERRAFORM_APPLY_FIN"
cd - >/dev/null || true

# -----------------------------------------------------------------------------
log "== 4. ArgoCD sincroniza el resto (app-of-apps)"
esperar 300 "aplicacion raiz sa-p9-root creada" kubectl get application sa-p9-root -n argocd
esperar 1800 "todas las Applications Synced/Healthy" todas_las_apps_ok || {
  kubectl get applications -n argocd | tee -a "$LOG"; falla "ArgoCD no convergio"; }
run kubectl get applications -n argocd
marca "ARGOCD_CONVERGIO"

# -----------------------------------------------------------------------------
log "== 5. Respaldo de la llave de Sealed Secrets (idempotente)"
"$P9_DIR/scripts/respaldar-llave.sh" 2>&1 | tee -a "$LOG"

# -----------------------------------------------------------------------------
log "== 6. Restauracion de datos desde el ultimo respaldo de Velero"
esperar 300 "BackupStorageLocation Available" \
  bash -c "kubectl get backupstoragelocation default -n velero -o jsonpath='{.status.phase}' | grep -q Available"
# Velero sincroniza los respaldos del bucket cada minuto: dar tiempo a que
# aparezcan los de la vida anterior del cluster.
esperar 150 "respaldos sincronizados desde MinIO" \
  bash -c "[ \$(kubectl get backups.velero.io -n velero --no-headers 2>/dev/null | wc -l) -gt 0 ]"
# Solo respaldos Completed tomados ANTES de este bootstrap (nunca uno del
# cluster recien creado, que tendria la base vacia).
ULTIMO=$(kubectl get backups.velero.io -n velero -o json 2>/dev/null | jq -r --argjson t0 "$T0" '
  [.items[] | select(.status.phase=="Completed")
            | select((.status.startTimestamp | fromdateiso8601) < $t0)]
  | sort_by(.status.startTimestamp) | last | .metadata.name // empty')
if [ -n "$ULTIMO" ]; then
  log "Ultimo respaldo valido: $ULTIMO ($(kubectl get backups.velero.io "$ULTIMO" -n velero -o jsonpath='{.status.startTimestamp}'))"
  marca "RESTAURACION_DATOS_INICIO"
  "$P9_DIR/scripts/restaurar-datos.sh" "$ULTIMO" 2>&1 | tee -a "$LOG" || falla "restauracion de datos"
  marca "RESTAURACION_DATOS_FIN"
else
  log "AVISO: no existe respaldo previo -> base de datos nueva (primer arranque)"
fi

# -----------------------------------------------------------------------------
log "== 7. Verificacion final"
esperar 600 "todas las Applications Synced/Healthy" todas_las_apps_ok
run kubectl get sealedsecrets -A
NO_SYNC=$(kubectl get sealedsecrets -A -o json | jq '[.items[] | select(([.status.conditions[]? | select(.type=="Synced" and .status=="True")] | length) == 0)] | length')
[ "$NO_SYNC" = "0" ] && log "OK: todos los SealedSecrets descifrados con la llave restaurada" \
                     || log "FALLA: $NO_SYNC SealedSecret(s) sin descifrar"
asegurar_sondeo
if H=$(gateway_health); then log "OK: api-gateway /health -> $H"; else log "FALLA: api-gateway no responde"; fi
MARCAS=$(psql_pg productos_db "SELECT count(*) FROM dr_marcas" 2>/dev/null || echo "sin tabla")
log "Filas en productos_db.dr_marcas: $MARCAS"
run kubectl get pods -n "$APP_NS" -o wide
run velero schedule get

TFIN=$(date +%s)
marca "FIN_BOOTSTRAP"
log "Duracion del bootstrap: $((TFIN - T0)) s"
if [ -f "$SA_P9_HOME/ultima-destruccion" ]; then
  TD=$(cut -d' ' -f1 "$SA_P9_HOME/ultima-destruccion")
  if [ "$TD" -lt "$T0" ]; then
    log "RTO MEDIDO (destruccion -> servicio restaurado y verificado): $((TFIN - TD)) s = $(( (TFIN - TD) / 60 )) min $(( (TFIN - TD) % 60 )) s"
  fi
fi
log "Registro: $LOG"
