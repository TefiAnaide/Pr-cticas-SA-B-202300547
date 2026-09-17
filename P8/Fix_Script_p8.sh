set -uo pipefail

VERSION="2.0"
CONF="p8.conf"

# ---------------------------------------------------------------------------
# Plantilla de configuracion
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--init" ]; then
  if [ -f "$CONF" ]; then echo "Ya existe $CONF. Borrelo si desea regenerarlo."; exit 1; fi
  cat > "$CONF" <<'PLANTILLA'
# Datos de la entrega de la Practica 8.
# Deben coincidir EXACTAMENTE con la tabla 4.1 del README de su entrega.

CARNET="202012345"
REPO_CODE="https://github.com/usuario/software-avanzado"
REPO_GITOPS="https://github.com/usuario/software-avanzado-gitops"
APP="mi-app-prod"                       # nombre de la aplicacion en ArgoCD
NS="produccion"                         # namespace de la aplicacion
IMAGE="ghcr.io/usuario/orders:1.4.2"    # imagen firmada, con tag concreto

# Identidad con la que se firmo la imagen (Cosign keyless).
# Si firma desde GitHub Actions, deje el issuer tal cual y ajuste el repositorio.
COSIGN_IDENTITY_REGEXP="https://github.com/usuario/software-avanzado/.*"
COSIGN_ISSUER="https://token.actions.githubusercontent.com"
PLANTILLA
  echo "Creado $CONF. Llenelo y vuelva a ejecutar el script sin argumentos."
  exit 0
fi

if [ ! -f "$CONF" ]; then
  echo "ERROR: no se encuentra $CONF en $(pwd)"
  echo "       Ejecute:  ./verificar_p8.sh --init"
  exit 1
fi
# shellcheck disable=SC1090
source "./$CONF"

: "${CARNET:?Falta CARNET en p8.conf}"
: "${REPO_CODE:?Falta REPO_CODE en p8.conf}"
: "${REPO_GITOPS:?Falta REPO_GITOPS en p8.conf}"
: "${APP:?Falta APP en p8.conf}"
: "${NS:?Falta NS en p8.conf}"
: "${IMAGE:?Falta IMAGE en p8.conf}"
COSIGN_IDENTITY_REGEXP="${COSIGN_IDENTITY_REGEXP:-.*}"
COSIGN_ISSUER="${COSIGN_ISSUER:-https://token.actions.githubusercontent.com}"

WORK=$(mktemp -d /tmp/p8_XXXXXX)
REPORTE="reporte_p8_${CARNET}.txt"
CSV="resultados_p8.csv"
INICIO=$(date +%s)

# ---------------------------------------------------------------------------
# Salida
# ---------------------------------------------------------------------------
if [ -t 1 ]; then V='\033[0;32m'; R='\033[0;31m'; A='\033[0;33m'; N='\033[0m'
else V=''; R=''; A=''; N=''; fi

exec > >(tee "$REPORTE") 2>&1

ok()   { printf "  ${V}[OK]${N}    %s\n" "$1"; }
bad()  { printf "  ${R}[FALLA]${N} %s\n" "$1"; }
avi()  { printf "  ${A}[AVISO]${N} %s\n" "$1"; }
sec()  { echo ""; echo "--- $1"; }

T=0; H=0; G=0; RO_=0; VA=0; S=0    # puntos por criterio
DIRECT_OK=0; ELIM=""               # estado de los requisitos eliminatorios

echo "================================================================"
echo " VERIFICACION PRACTICA 8 - v$VERSION"
echo " Carnet: $CARNET        Fecha: $(date '+%Y-%m-%d %H:%M')"
echo " Hash del script: $(sha256sum "$0" 2>/dev/null | cut -c1-16)"
echo "================================================================"

# ---------------------------------------------------------------------------
sec "0. Herramientas y contexto (debe verificarlo el auxiliar)"
FALTAN=""
for t in git jq kubectl helm terraform trivy cosign argocd; do
  command -v "$t" >/dev/null 2>&1 || FALTAN="$FALTAN $t"
done
kubectl argo rollouts version >/dev/null 2>&1 || FALTAN="$FALTAN kubectl-argo-rollouts"
if [ -n "$FALTAN" ]; then
  avi "Herramientas ausentes:$FALTAN  (sus verificaciones saldran en cero)"
else
  ok "Todas las herramientas presentes"
fi

CTX=$(kubectl config current-context 2>/dev/null || echo "sin contexto")
SRV=$(kubectl cluster-info 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*m//g' || true)
echo "  Contexto de kubectl : $CTX"
echo "  Servidor            : ${SRV:-no accesible}"
echo "  Usuario de ArgoCD   : $(argocd account get-user-info 2>/dev/null | head -1 || echo 'sin sesion')"
kubectl get ns >/dev/null 2>&1 && ok "Acceso al cluster confirmado" \
  || { bad "SIN ACCESO AL CLUSTER: el estudiante debe tenerlo encendido y conectado"; }

# ---------------------------------------------------------------------------
sec "1. Repositorios"
git clone --quiet --depth 1 "$REPO_CODE" "$WORK/code" 2>/dev/null \
  && ok "Repositorio de codigo accesible" \
  || { bad "Repositorio de codigo INACCESIBLE: $REPO_CODE"; ELIM="$ELIM repo-codigo"; }
git clone --quiet --depth 1 "$REPO_GITOPS" "$WORK/gitops" 2>/dev/null \
  && ok "Repositorio GitOps accesible" \
  || { bad "Repositorio GitOps INACCESIBLE: $REPO_GITOPS"; ELIM="$ELIM repo-gitops"; }

CODE="$WORK/code"; GITOPS="$WORK/gitops"; WF="$CODE/.github/workflows"
P8="$CODE/P8"
[ -d "$P8" ] && ok "Carpeta /P8 presente" || bad "No existe la carpeta /P8"
[ -f "$P8/README.md" ] && ok "README de entrega presente" \
  || { bad "README de entrega AUSENTE"; ELIM="$ELIM readme"; }

# ---------------------------------------------------------------------------
sec "ELIMINATORIO: ausencia de despliegue directo (seccion 8.1)"
VIOL=$(grep -rIl -E 'kubectl[[:space:]]+(apply|set[[:space:]]+image|patch|create|delete)|helm[[:space:]]+(upgrade|install)|KUBE_CONFIG|kubeconfig|KUBECONFIG' \
        "$WF" 2>/dev/null)
if [ -z "$VIOL" ] && [ -d "$WF" ]; then
  ok "Ningun workflow despliega directamente ni almacena kubeconfig"
  DIRECT_OK=1
elif [ ! -d "$WF" ]; then
  bad "No existe .github/workflows en el repositorio de codigo"
  ELIM="$ELIM sin-workflows"
else
  bad "DESPLIEGUE DIRECTO detectado en:"
  echo "$VIOL" | sed 's|'"$CODE"'/|         |'
  ELIM="$ELIM despliegue-directo"
fi

# ---------------------------------------------------------------------------
sec "2.1 Infraestructura como codigo con Terraform (8 pts)"
mapfile -t TFDIRS < <(find "$CODE" -name '*.tf' -printf '%h\n' 2>/dev/null | sort -u)
if [ "${#TFDIRS[@]}" -gt 0 ]; then
  ok "Codigo Terraform encontrado en ${#TFDIRS[@]} directorio(s)"; T=$((T+3))
  VALIDO=0
  for d in "${TFDIRS[@]}"; do
    ( cd "$d" && terraform init -backend=false -input=false >/dev/null 2>&1 \
      && terraform validate >/dev/null 2>&1 ) && { VALIDO=1; break; }
  done
  [ "$VALIDO" = 1 ] && { ok "terraform validate correcto"; T=$((T+2)); } \
                    || bad "terraform validate falla en todos los directorios"
  grep -rqE 'kubernetes_namespace|kubernetes_resource_quota|kubernetes_limit_range' "$CODE" 2>/dev/null \
    && { ok "Declara namespaces, cuotas o limites"; T=$((T+2)); } \
    || bad "No declara namespaces, cuotas ni limites"
  grep -rqE 'kubernetes_role|kubernetes_role_binding|kubernetes_cluster_role|kubernetes_service_account' "$CODE" 2>/dev/null \
    && { ok "Declara RBAC"; T=$((T+1)); } || bad "No declara RBAC"
else
  bad "Sin codigo Terraform en el repositorio"
fi
echo "  >> 2.1 = $T / 8"

# ---------------------------------------------------------------------------
sec "2.2 Empaquetado con Helm (8 pts)"
mapfile -t CHARTS < <(find "$GITOPS" "$CODE" -name 'Chart.yaml' 2>/dev/null)
NCH=${#CHARTS[@]}
RAICES=(); NSUB=0
for c in "${CHARTS[@]}"; do
  d=$(dirname "$c")
  if [ "$(basename "$(dirname "$d")")" = "charts" ] && [ -f "$(dirname "$(dirname "$d")")/Chart.yaml" ]; then
    NSUB=$((NSUB+1))
  else
    RAICES+=("$d")
  fi
done
if [ "$NCH" -ge 1 ]; then
  ok "$NCH chart(s): ${#RAICES[@]} raiz/raices y $NSUB subchart(s)"; H=$((H+2))
  if [ "$NCH" -ge 2 ]; then
    ok "Multiples servicios empaquetados"; H=$((H+1))
  else
    avi "Un solo chart y sin subcharts: verificar que cubra todos los servicios"
  fi
  ALL_LINT=1
  command -v helm >/dev/null 2>&1 || ALL_LINT=0
  for d in "${RAICES[@]}"; do
    # --with-subcharts valida tambien los subcharts, pero renderizando desde la
    # raiz, que es como Helm los resuelve realmente.
    helm lint --with-subcharts "$d" >/dev/null 2>&1 \
      || helm lint "$d" >/dev/null 2>&1 \
      || { ALL_LINT=0; avi "helm lint falla en $(echo "$d" | sed "s|$WORK/||")"; }
  done
  [ "$ALL_LINT" = 1 ] && { ok "helm lint correcto en los charts raiz"; H=$((H+2)); } \
                      || bad "helm lint falla en al menos un chart raiz"
  NVAL=$(find "$GITOPS" "$CODE" \( -name 'values-*.y*ml' -o -name 'values.*.y*ml' \) 2>/dev/null | wc -l)
  [ "$NVAL" -ge 2 ] && { ok "Valores diferenciados por ambiente ($NVAL archivos)"; H=$((H+2)); } \
                    || bad "Menos de dos archivos de values por ambiente"
  grep -rq 'helm lint' "$WF" 2>/dev/null \
    && { ok "helm lint integrado en el pipeline"; H=$((H+1)); } \
    || bad "helm lint no esta en el pipeline"
else
  bad "Sin charts de Helm"
fi
echo "  >> 2.2 = $H / 8"

# ---------------------------------------------------------------------------
sec "2.3 GitOps con ArgoCD (14 pts)"
[ "$DIRECT_OK" = 1 ] && G=$((G+5))
APPJSON=$(argocd app get "$APP" -o json 2>/dev/null)
if [ -z "$APPJSON" ]; then
  APPJSON=$(kubectl get application "$APP" -n argocd -o json 2>/dev/null)
  [ -n "$APPJSON" ] && avi "Sin sesion de argocd: se consulto el CRD Application directamente"
fi
if [ -n "$APPJSON" ]; then
  SYNC=$(echo "$APPJSON"    | jq -r '.status.sync.status // "?"')
  HEALTH=$(echo "$APPJSON"  | jq -r '.status.health.status // "?"')
  REPOURL=$(echo "$APPJSON" | jq -r '.spec.source.repoURL // .spec.sources[0].repoURL // "?"')
  AUTO=$(echo "$APPJSON"    | jq -r 'if .spec.syncPolicy.automated then "si" else "no" end')
  echo "  sync=$SYNC  health=$HEALTH  automated=$AUTO"
  echo "  repoURL=$REPOURL"
  [ "$SYNC" = "Synced" ]     && { ok "Aplicacion sincronizada"; G=$((G+3)); } \
    || { bad "Aplicacion NO sincronizada"; ELIM="$ELIM no-synced"; }
  [ "$HEALTH" = "Healthy" ]  && { ok "Aplicacion saludable"; G=$((G+2)); } \
    || { bad "Aplicacion NO saludable"; ELIM="$ELIM no-healthy"; }
  BASE=$(basename "$REPO_GITOPS" .git)
  case "$REPOURL" in
    *"$BASE"*) ok "Apunta al repositorio GitOps declarado"; G=$((G+2));;
    *)         bad "El repoURL NO coincide con el repositorio GitOps entregado";;
  esac
else
  bad "No se pudo obtener la aplicacion '$APP' (ni por argocd ni por kubectl)"
  ELIM="$ELIM sin-app-argocd"
fi
grep -rqE 'peter-evans/create-pull-request|gh pr create|create-pull-request' "$WF" 2>/dev/null \
  && { ok "El pipeline genera un Pull Request al repositorio GitOps"; G=$((G+2)); } \
  || bad "No se evidencia actualizacion de version mediante Pull Request"
echo "  >> 2.3 = $G / 14"

# ---------------------------------------------------------------------------
sec "2.4 Entrega progresiva y reversion automatica (14 pts)"
RO=$(kubectl get rollouts -n "$NS" -o name 2>/dev/null | head -1)
if [ -n "$RO" ]; then
  RONAME=$(basename "$RO")
  ok "Rollout encontrado: $RONAME"; RO_=$((RO_+3))
  RJSON=$(kubectl get "$RO" -n "$NS" -o json 2>/dev/null)
  STRAT=$(echo "$RJSON" | jq -r '.spec.strategy | keys[0] // "?"')
  STEPS=$(echo "$RJSON" | jq -r '.spec.strategy.canary.steps | length // 0' 2>/dev/null || echo 0)
  echo "  Estrategia: $STRAT   pasos declarados: $STEPS"
  NPESOS=$(echo "$RJSON" | jq '[.spec.strategy.canary.steps[]? | select(.setWeight)] | length' 2>/dev/null || echo 0)
  [ "${NPESOS:-0}" -ge 3 ] && { ok "Tres o mas pasos de promocion"; RO_=$((RO_+3)); } \
                           || bad "Menos de tres pasos de promocion (setWeight: ${NPESOS:-0})"
  NAT=$(kubectl get analysistemplates -n "$NS" -o name 2>/dev/null | wc -l)
  [ "$NAT" -ge 1 ] && { ok "AnalysisTemplate definido ($NAT)"; RO_=$((RO_+3)); } \
                   || bad "Sin AnalysisTemplate en el namespace"
  echo "$RJSON" | jq -e '.spec.strategy.canary.steps[]?.analysis' >/dev/null 2>&1 \
    && { ok "La promocion esta condicionada al analisis"; RO_=$((RO_+3)); } \
    || bad "La promocion NO depende del analisis"
  # evidencia de reversion: AnalysisRun fallido o revision abortada
  NFAIL=$(kubectl get analysisruns -n "$NS" -o json 2>/dev/null \
          | jq '[.items[]? | select(.status.phase=="Failed" or .status.phase=="Error")] | length' 2>/dev/null || echo 0)
  ABORT=$(echo "$RJSON" | jq -r '.status.abort // false')
  if [ "${NFAIL:-0}" -ge 1 ] || [ "$ABORT" = "true" ]; then
    ok "Evidencia de reversion: $NFAIL AnalysisRun fallido(s), abort=$ABORT"; RO_=$((RO_+2))
  else
    bad "Sin evidencia de reversion en el cluster -> EXIGIR LA DEMOSTRACION EN VIVO"
  fi
  echo ""
  kubectl argo rollouts get rollout "$RONAME" -n "$NS" 2>/dev/null | head -30
else
  bad "No existe ningun Rollout en el namespace '$NS'"
  ELIM="$ELIM sin-rollout"
fi
echo "  >> 2.4 = $RO_ / 14"

# ---------------------------------------------------------------------------
sec "2.5 Validacion automatizada (8 pts)"
find "$CODE" \( -iname '*k6*' -o -iname 'locustfile*' \) 2>/dev/null | grep -q . \
  && { ok "Prueba de carga presente"; VA=$((VA+2)); } || bad "Sin prueba de carga (k6 o Locust)"
grep -rqE 'http_req_duration|thresholds|p\(95\)|percentile' "$CODE" 2>/dev/null \
  && { ok "Umbrales definidos"; VA=$((VA+2)); } || bad "Sin umbrales de error o latencia"
find "$CODE" -path '*test*' -type f 2>/dev/null | grep -q . \
  && { ok "Pruebas de humo o integracion presentes"; VA=$((VA+2)); } || bad "Sin pruebas de humo"
if kubectl get analysistemplates -n "$NS" -o json 2>/dev/null \
   | jq -e '.items[]?.spec.metrics[]? | select(.provider.job or .provider.web)' >/dev/null 2>&1; then
  ok "El analisis ejecuta pruebas (provider job/web)"; VA=$((VA+2))
else
  bad "El analisis no invoca pruebas reales"
fi
echo "  >> 2.5 = $VA / 8"

# ---------------------------------------------------------------------------
sec "2.6 Cadena de suministro y politicas (8 pts)"
if grep -rqE 'aquasecurity/trivy|trivy image' "$WF" 2>/dev/null \
   && grep -rqE "exit-code|severity.*CRITICAL" "$WF" 2>/dev/null; then
  ok "Trivy configurado para bloquear ante CVE criticas"; S=$((S+2))
else
  bad "Trivy ausente o sin capacidad de bloqueo"
fi
if cosign verify "$IMAGE" \
     --certificate-identity-regexp "$COSIGN_IDENTITY_REGEXP" \
     --certificate-oidc-issuer "$COSIGN_ISSUER" >/dev/null 2>&1; then
  ok "Firma de imagen verificada con Cosign"; S=$((S+2))
else
  bad "Imagen sin firma valida (o registro privado sin docker login)"
  avi "Reintente a mano: cosign verify $IMAGE --certificate-identity-regexp '$COSIGN_IDENTITY_REGEXP' --certificate-oidc-issuer $COSIGN_ISSUER"
fi
NPOL=$( { kubectl get clusterpolicy -o name 2>/dev/null; \
          kubectl get constrainttemplates -o name 2>/dev/null; } | grep -c . )
echo "  Politicas activas: $NPOL"
[ "$NPOL" -ge 3 ] && { ok "Tres o mas politicas activas"; S=$((S+2)); } \
                  || bad "Menos de tres politicas activas en el cluster"
grep -rqE 'kind:[[:space:]]*(SealedSecret|ExternalSecret)' "$GITOPS" 2>/dev/null \
  && { ok "Secretos gestionados de forma segura"; S=$((S+1)); } \
  || bad "Sin SealedSecrets ni ExternalSecrets"
if grep -rqE '^[[:space:]]*(password|passwd|token|apiKey|secretKey|clientSecret)[[:space:]]*:[[:space:]]*[^ {$]' "$GITOPS" 2>/dev/null; then
  bad "POSIBLES SECRETOS EN TEXTO PLANO en el repositorio GitOps:"
  grep -rnE '^[[:space:]]*(password|passwd|token|apiKey|secretKey|clientSecret)[[:space:]]*:' "$GITOPS" 2>/dev/null \
    | sed "s|$GITOPS/|         |" | head -5
  ELIM="$ELIM secretos-planos"
else
  ok "Sin secretos en texto plano"; S=$((S+1))
fi
echo "  >> 2.6 = $S / 8"

# ---------------------------------------------------------------------------
sec "Antipatrones (informativo, penalizacion manual)"
grep -rqE 'image:.*:latest' "$GITOPS" 2>/dev/null \
  && bad "Uso de la etiqueta latest en manifiestos (-5 pts segun seccion 8)" \
  || ok "Sin uso de la etiqueta latest"
grep -rq 'limits:' "$GITOPS" 2>/dev/null \
  && ok "Se declaran limites de recursos" || bad "Sin limites de recursos declarados"

# ---------------------------------------------------------------------------
TOTAL=$((T + H + G + RO_ + VA + S))
DUR=$(( $(date +%s) - INICIO ))

echo ""
echo "================================================================"
echo " RESUMEN - carnet $CARNET"
echo "================================================================"
printf "  2.1 Terraform .............. %2d / 8\n"  "$T"
printf "  2.2 Helm ................... %2d / 8\n"  "$H"
printf "  2.3 GitOps con ArgoCD ...... %2d / 14\n" "$G"
printf "  2.4 Entrega progresiva ..... %2d / 14\n" "$RO_"
printf "  2.5 Validacion automatizada  %2d / 8\n"  "$VA"
printf "  2.6 Seguridad y politicas .. %2d / 8\n"  "$S"
echo   "  ------------------------------------"
printf "  CONOCIMIENTO ............... %2d / 60\n" "$TOTAL"
echo ""
echo "  Pendiente de evaluacion presencial: 40 pts"
echo "    1.1 Documentacion (8)   1.2 Diagrama (8)"
echo "    1.3 Informe de incidente (10)   1.4 Preguntas teoricas (14)"
echo ""
if [ -n "$ELIM" ]; then
  printf "  ${R}REQUISITOS ELIMINATORIOS INCUMPLIDOS:${N}%s\n" "$ELIM"
  echo "  Revisar la seccion 8.1 del enunciado antes de asignar nota."
else
  printf "  ${V}Requisitos eliminatorios: todos cumplidos${N}\n"
fi
echo ""
echo "  Duracion: ${DUR}s    Reporte: $REPORTE"
echo "================================================================"

[ -f "$CSV" ] || echo "carnet,terraform,helm,gitops,rollouts,validacion,seguridad,total60,eliminatorios" > "$CSV"
echo "$CARNET,$T,$H,$G,$RO_,$VA,$S,$TOTAL,\"${ELIM:-ninguno}\"" >> "$CSV"
rm -rf "$WORK"
