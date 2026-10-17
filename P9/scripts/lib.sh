# Funciones y constantes comunes de los scripts de la Practica 9.
# Uso: source "$(dirname "$0")/scripts/lib.sh"   (o ../scripts/lib.sh)

P9_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SA_P9_HOME="$HOME/.sa-p9"                     # todo lo sensible vive aqui, fuera del repo
CLUSTER="sa-p9"
export KUBECONFIG="$HOME/.kube/sa-p9.config"
MINIO_ENV="$SA_P9_HOME/minio.env"
MINIO_URL="http://localhost:9100"
BUCKET_TFSTATE="sa-p9-tfstate"
BUCKET_VELERO="sa-p9-velero"
BUCKET_LLAVES="sa-p9-llaves"
LLAVES_DIR="$SA_P9_HOME/sealed-secrets"
EVIDENCIAS="$P9_DIR/evidencias"
APP_NS="sa-p8"
SCHEDULE="velero-sa-p8-cada-hora"

mkdir -p "$SA_P9_HOME" "$EVIDENCIAS" && chmod 700 "$SA_P9_HOME"

# ---------------------------------------------------------------------------
# Registro con marcas de tiempo. Cada linea: ISO-8601 local + epoch.
# LOG debe definirlo el script que hace source (archivo en evidencias/).
ts()    { date '+%Y-%m-%dT%H:%M:%S%z'; }
log()   { printf '[%s] [%s] %s\n' "$(ts)" "$(date +%s)" "$*" | tee -a "${LOG:-/dev/null}"; }
marca() { printf '[%s] [%s] MARCA %s\n' "$(ts)" "$(date +%s)" "$*" | tee -a "${LOG:-/dev/null}"; }
falla() { log "ERROR: $*"; exit 1; }

# Ejecuta un comando dejando su salida en el log.
run() { log "\$ $*"; "$@" 2>&1 | tee -a "${LOG:-/dev/null}"; return "${PIPESTATUS[0]}"; }

# ---------------------------------------------------------------------------
# Credenciales de MinIO (se generan una sola vez) y su exportacion como
# credenciales S3 para Terraform (backend) y el AWS CLI.
cargar_credenciales() {
  if [ ! -f "$MINIO_ENV" ]; then
    umask 077
    {
      echo "MINIO_ROOT_USER=sa-p9-admin"
      echo "MINIO_ROOT_PASSWORD=$(openssl rand -hex 24)"
    } > "$MINIO_ENV"
    log "Credenciales de MinIO generadas en $MINIO_ENV"
  fi
  # shellcheck disable=SC1090
  set -a; . "$MINIO_ENV"; set +a
  export AWS_ACCESS_KEY_ID="$MINIO_ROOT_USER"
  export AWS_SECRET_ACCESS_KEY="$MINIO_ROOT_PASSWORD"
  export AWS_DEFAULT_REGION="us-east-1"
  export AWS_EC2_METADATA_DISABLED=true
}

s3() { aws --endpoint-url "$MINIO_URL" "$@"; }

# ---------------------------------------------------------------------------
# Espera generica: esperar <segundos> <descripcion> <comando...>
esperar() {
  local limite=$1 desc=$2; shift 2
  local inicio; inicio=$(date +%s)
  until "$@" >/dev/null 2>&1; do
    if [ $(( $(date +%s) - inicio )) -ge "$limite" ]; then
      log "TIMEOUT (${limite}s) esperando: $desc"; return 1
    fi
    sleep 5
  done
  log "Listo: $desc ($(( $(date +%s) - inicio ))s)"
}

app_ok() {  # app_ok <application>  -> Synced + Healthy
  local s
  s=$(kubectl get application "$1" -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
  [ "$s" = "Synced/Healthy" ]
}

todas_las_apps_ok() {
  local total malas
  total=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
  malas=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -vc 'Synced *Healthy')
  [ "$total" -ge 7 ] && [ "$malas" -eq 0 ]
}

# Sonda del api-gateway: un pod curl en el namespace sa-p9-sondeo (permitido
# por chart/templates/networkpolicy-p9.yaml del repo GitOps), fijado al
# control-plane para que un drenaje de worker no lo desaloje. Consulta el
# Service (no un pod concreto, como haria un port-forward).
asegurar_sondeo() {
  kubectl get pod sondeo -n sa-p9-sondeo >/dev/null 2>&1 && return 0
  kubectl create namespace sa-p9-sondeo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sondeo
  namespace: sa-p9-sondeo
spec:
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
  containers:
    - name: curl
      image: curlimages/curl:8.16.0
      command: ["sleep", "infinity"]
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {cpu: 100m, memory: 32Mi}
EOF
  kubectl wait --for=condition=Ready pod/sondeo -n sa-p9-sondeo --timeout=120s >/dev/null
}

gateway_health() {
  kubectl exec -n sa-p9-sondeo sondeo -- curl -fsS -m 2 "http://api-gateway.$APP_NS.svc.cluster.local:8080/health"
}

psql_pg() {  # psql_pg <base> <sql>
  kubectl exec -n "$APP_NS" postgres-0 -c postgresql -- \
    bash -c "PGPASSWORD=\$(cat \$POSTGRES_PASSWORD_FILE) psql -U postgres -d $1 -tAc \"$2\""
}
