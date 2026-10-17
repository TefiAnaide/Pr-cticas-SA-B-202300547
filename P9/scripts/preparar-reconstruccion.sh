#!/usr/bin/env bash
# Paso previo a la prueba de reconstruccion cronometrada (destruir.sh +
# bootstrap.sh). Deja datos de referencia para medir el RPO de una perdida
# TOTAL, no solo de la base:
#
#   1. Escribe 20 filas "pre-reconstruccion" en productos_db.dr_marcas.
#   2. Toma un respaldo con la plantilla del Schedule horario (el mismo que
#      elegira bootstrap.sh por ser el ultimo anterior a la reconstruccion).
#   3. Escribe 5 filas "post-respaldo": se DEBEN perder (estan despues del
#      ultimo respaldo). Tras el bootstrap, contar cuantas volvieron.
#
# Uso:  ./P9/scripts/preparar-reconstruccion.sh && ./P9/scripts/destruir.sh && ./P9/bootstrap.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$EVIDENCIAS/preparacion-reconstruccion-$(date +%Y%m%d-%H%M%S).log"
BACKUP="pre-reconstruccion-$(date +%Y%m%d-%H%M%S)"
HUELLA_SQL="SELECT encode(sha256(convert_to(string_agg(id::text || etapa || dato || creado::text, ',' ORDER BY id), 'UTF8')), 'hex') FROM dr_marcas"

marca "PREPARACION_INICIO"
psql_pg productos_db "CREATE TABLE IF NOT EXISTS dr_marcas (id serial PRIMARY KEY, etapa text NOT NULL, dato text NOT NULL, creado timestamptz NOT NULL DEFAULT now())" | tee -a "$LOG"
psql_pg productos_db "INSERT INTO dr_marcas (etapa, dato) SELECT 'pre-reconstruccion', gen_random_uuid()::text FROM generate_series(1,20)" | tee -a "$LOG"
N=$(psql_pg productos_db "SELECT count(*) FROM dr_marcas")
H=$(psql_pg productos_db "$HUELLA_SQL")
log "Referencia: dr_marcas=$N filas, huella $H"
log "Por etapa: $(psql_pg productos_db "SELECT etapa || '=' || count(*) FROM dr_marcas GROUP BY etapa ORDER BY etapa" | tr '\n' ' ')"

run velero backup create "$BACKUP" --from-schedule "$SCHEDULE" --wait
FASE=$(kubectl get backups.velero.io "$BACKUP" -n velero -o jsonpath='{.status.phase}')
T_ISO=$(kubectl get backups.velero.io "$BACKUP" -n velero -o jsonpath='{.status.startTimestamp}')
log "Respaldo $BACKUP -> $FASE (inicio $T_ISO, epoch $(date -d "$T_ISO" +%s))"
[ "$FASE" = "Completed" ] || falla "el respaldo no quedo Completed"

sleep 15
psql_pg productos_db "INSERT INTO dr_marcas (etapa, dato) SELECT 'post-respaldo', gen_random_uuid()::text FROM generate_series(1,5)" | tee -a "$LOG"
log "Escritas 5 filas post-respaldo (deben perderse). Total ahora: $(psql_pg productos_db "SELECT count(*) FROM dr_marcas")"
echo "$BACKUP $(date -d "$T_ISO" +%s) $N $H" > "$SA_P9_HOME/ultima-preparacion"
marca "PREPARACION_FIN"
log "Siguiente paso: ./P9/scripts/destruir.sh && ./P9/bootstrap.sh"
