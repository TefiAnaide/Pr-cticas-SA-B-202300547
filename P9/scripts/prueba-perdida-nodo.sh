#!/usr/bin/env bash
# Prueba de perdida de nodo (Practica 9, seccion 3.2).
#
# Drena un worker que aloja una replica del api-gateway mientras un sondeo
# consulta /health cada segundo A TRAVES DEL SERVICE (proxy del API server,
# que corre en el control-plane y no se ve afectado por el drenaje).
# Resultado: cuantas peticiones fallaron durante el drenaje.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$EVIDENCIAS/perdida-nodo-$(date +%Y%m%d-%H%M%S).log"
SONDEO="$EVIDENCIAS/.sondeo-$$.txt"

marca "PRUEBA_NODO_INICIO"
log "== Distribucion inicial"
run kubectl get pods -n "$APP_NS" -l app.kubernetes.io/name=api-gateway -o wide
run kubectl get pdb -n "$APP_NS"

# Nodo objetivo: un worker con api-gateway; se prefiere uno SIN postgres-0,
# porque el volumen local de Postgres esta atado a su nodo (ver informe DR,
# punto unico de fallo) y aqui se prueba la resiliencia del servicio sin estado.
NODO_PG=$(kubectl get pod postgres-0 -n "$APP_NS" -o jsonpath='{.spec.nodeName}')
mapfile -t NODOS_GW < <(kubectl get pods -n "$APP_NS" -l app.kubernetes.io/name=api-gateway -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u)
[ "${#NODOS_GW[@]}" -ge 2 ] || log "AVISO: las replicas del api-gateway NO estan repartidas en 2 nodos"
NODO="${1:-}"   # opcional: forzar el nodo a drenar
for n in "${NODOS_GW[@]}"; do [ -z "$NODO" ] && [ "$n" != "$NODO_PG" ] && NODO="$n"; done
NODO="${NODO:-${NODOS_GW[0]}}"
log "Nodo a drenar: $NODO (postgres-0 esta en $NODO_PG)"

asegurar_sondeo
log "== Sondeo continuo de /health (1/s)"
( while :; do
    if gateway_health >/dev/null 2>&1; then r=OK; else r=FALLA; fi
    echo "$(date '+%H:%M:%S') $(date +%s) $r"
    sleep 1
  done ) > "$SONDEO" &
PID=$!
sleep 10

marca "DRENAJE_INICIO $NODO"
run kubectl drain "$NODO" --ignore-daemonsets --delete-emptydir-data --timeout=240s
marca "DRENAJE_FIN $NODO"
run kubectl get pods -n "$APP_NS" -l app.kubernetes.io/name=api-gateway -o wide
sleep 20

kill "$PID" 2>/dev/null
marca "NODO_RESTAURADO $NODO"
run kubectl uncordon "$NODO"

cat "$SONDEO" >> "$LOG"
TOTAL=$(wc -l < "$SONDEO"); FALLAS=$(grep -c FALLA "$SONDEO")
rm -f "$SONDEO"
log "Peticiones: $TOTAL, fallidas: $FALLAS, disponibilidad: $(awk -v t="$TOTAL" -v f="$FALLAS" 'BEGIN{printf "%.2f", (t-f)*100/t}')%"
run kubectl get pods -n "$APP_NS" -o wide
marca "PRUEBA_NODO_FIN"
log "Registro: $LOG"
