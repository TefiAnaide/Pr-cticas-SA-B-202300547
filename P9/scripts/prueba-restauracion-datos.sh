#!/usr/bin/env bash
# Prueba de restauracion de datos (Practica 9, seccion 3.2) y medicion del RPO.
#
#   1. Escribe filas marcadas "antes-del-respaldo" (con huella sha256).
#   2. Toma un respaldo con la MISMA configuracion del Schedule.
#   3. Escribe filas "despues-del-respaldo" (estas se DEBEN perder: es el RPO).
#   4. DESASTRE: borra los datos (DROP TABLE) y luego el volumen completo.
#   5. Restaura con scripts/restaurar-datos.sh (el mismo que usa bootstrap.sh).
#   6. Verifica contenido real (huella sha256 identica), no solo que el volumen exista.
#   7. RPO medido = instante del desastre - instante en que empezo el respaldo.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$EVIDENCIAS/restauracion-datos-$(date +%Y%m%d-%H%M%S).log"
BACKUP="prueba-datos-$(date +%Y%m%d-%H%M%S)"
# sha256 y no md5: la imagen de Bitnami usa OpenSSL en modo FIPS (md5 no disponible).
HUELLA_SQL="SELECT encode(sha256(convert_to(string_agg(id::text || etapa || dato || creado::text, ',' ORDER BY id), 'UTF8')), 'hex') FROM dr_marcas"

marca "PRUEBA_RESTAURACION_INICIO"
log "== 1. Datos de referencia"
psql_pg productos_db "CREATE TABLE IF NOT EXISTS dr_marcas (id serial PRIMARY KEY, etapa text NOT NULL, dato text NOT NULL, creado timestamptz NOT NULL DEFAULT now())" | tee -a "$LOG"
psql_pg productos_db "INSERT INTO dr_marcas (etapa, dato) SELECT 'antes-del-respaldo', gen_random_uuid()::text FROM generate_series(1,50)" | tee -a "$LOG"
psql_pg productos_db "INSERT INTO productos (id, nombre, descripcion, precio, stock, categoria) VALUES (gen_random_uuid(), 'Producto DR $(date +%H%M%S)', 'fila de verificacion P9', 99.99, 7, 'dr') ON CONFLICT DO NOTHING" | tee -a "$LOG"
ANTES_N=$(psql_pg productos_db "SELECT count(*) FROM dr_marcas")
ANTES_H=$(psql_pg productos_db "$HUELLA_SQL")
PROD_N=$(psql_pg productos_db "SELECT count(*) FROM productos")
log "dr_marcas: $ANTES_N filas, huella $ANTES_H | productos: $PROD_N filas"

log "== 2. Respaldo (misma plantilla que el Schedule $SCHEDULE)"
run velero backup create "$BACKUP" --from-schedule "$SCHEDULE" --wait
FASE=$(kubectl get backups.velero.io "$BACKUP" -n velero -o jsonpath='{.status.phase}')
T_BACKUP_ISO=$(kubectl get backups.velero.io "$BACKUP" -n velero -o jsonpath='{.status.startTimestamp}')
T_BACKUP=$(date -d "$T_BACKUP_ISO" +%s)
log "Respaldo $BACKUP -> $FASE (inicio $T_BACKUP_ISO)"
[ "$FASE" = "Completed" ] || falla "el respaldo no quedo Completed"
velero backup describe "$BACKUP" --details | grep -A6 -i 'Pod Volume Backups' | tee -a "$LOG"

log "== 3. Escrituras posteriores al respaldo (se perderan)"
sleep 20
psql_pg productos_db "INSERT INTO dr_marcas (etapa, dato) SELECT 'despues-del-respaldo', gen_random_uuid()::text FROM generate_series(1,5)" | tee -a "$LOG"
log "dr_marcas ahora: $(psql_pg productos_db "SELECT etapa || '=' || count(*) FROM dr_marcas GROUP BY etapa ORDER BY etapa" | tr '\n' ' ')"

log "== 4. DESASTRE: eliminacion de datos"
T_DESASTRE=$(date +%s)
marca "DESASTRE_DATOS"
psql_pg productos_db "DROP TABLE dr_marcas; DELETE FROM productos" | tee -a "$LOG"
log "Tras el borrado: productos=$(psql_pg productos_db "SELECT count(*) FROM productos"), dr_marcas=$(psql_pg productos_db "SELECT count(*) FROM dr_marcas" 2>&1 | tail -1)"

log "== 5. Restauracion desde $BACKUP"
marca "RESTAURACION_INICIO"
"$(dirname "$0")/restaurar-datos.sh" "$BACKUP" 2>&1 | tee -a "$LOG"
T_RESTAURADO=$(date +%s)
marca "RESTAURACION_FIN"

log "== 6. Verificacion del contenido"
DESPUES_N=$(psql_pg productos_db "SELECT count(*) FROM dr_marcas")
DESPUES_H=$(psql_pg productos_db "$HUELLA_SQL")
PERDIDAS=$(psql_pg productos_db "SELECT count(*) FROM dr_marcas WHERE etapa='despues-del-respaldo'")
PROD_D=$(psql_pg productos_db "SELECT count(*) FROM productos")
log "dr_marcas: $DESPUES_N filas (antes $ANTES_N), huella $DESPUES_H (antes $ANTES_H)"
log "productos: $PROD_D filas (antes $PROD_N)"
log "filas 'despues-del-respaldo' presentes: $PERDIDAS (esperado 0: escritas despues del respaldo)"
if [ "$ANTES_H" = "$DESPUES_H" ] && [ "$ANTES_N" = "$DESPUES_N" ] && [ "$PROD_N" = "$PROD_D" ]; then
  log "OK: contenido restaurado identico al del momento del respaldo"
else
  log "FALLA: el contenido restaurado NO coincide"
fi

log "== 7. Resultados"
log "RPO medido (desastre - inicio del respaldo): $((T_DESASTRE - T_BACKUP)) s -> se perdieron 5 filas escritas en esa ventana"
log "Tiempo de restauracion de datos: $((T_RESTAURADO - T_DESASTRE)) s"
log "Con el Schedule horario, el RPO en el peor caso es ~60 min (desastre justo antes del siguiente respaldo)."
marca "PRUEBA_RESTAURACION_FIN"
log "Registro: $LOG"
