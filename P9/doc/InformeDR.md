# Informe de la prueba de DR — Práctica 9

**Prueba:** pérdida total del clúster `sa-p9`, 2026-10-17, 07:33–07:48 (CST, UTC−6).
**Evidencia:** `P9/evidencias/preparacion-reconstruccion-20261017-073327.log`,
`destruccion-20261017-073505.log` y `reconstruccion-20261017-073520.log`.

## 1. Objetivos declarados

| Objetivo | Valor | Justificación |
|---|---|---|
| **RTO** | **30 min** | El bootstrap espera hasta 30 min (`esperar 1800`) a que ArgoCD converja: es el tiempo máximo que el diseño tolera. Incluye crear el clúster, descargar imágenes y charts de internet y restaurar la base. Es un sistema académico sin usuarios que paguen por la disponibilidad, así que media hora de corte es aceptable. Bajarlo exigiría infraestructura que no existe (clúster en espera, caché de imágenes). |
| **RPO** | **60 min** | Lo fija el Schedule `velero-sa-p8-cada-hora` (`0 * * * *`). En el peor caso el desastre ocurre justo antes del siguiente respaldo y se pierde una hora de escrituras. Ya estaba declarado así antes de esta prueba (`restauracion-datos-20260926-075749.log`: *"el RPO en el peor caso es ~60 min"*). |

## 2. Escenario ejecutado

En este orden, con un solo comando por paso:

1. **Datos de referencia** (`preparar-reconstruccion.sh`): 20 filas `pre-reconstruccion` en `productos_db.dr_marcas` (70 en total, huella sha256 `08584b8b…`). Respaldo `pre-reconstruccion-20261017-073327` con la plantilla del Schedule (inicio 07:33:44). Luego, **5 filas `post-respaldo` que deben perderse**.
2. **Destrucción** (`destruir.sh`): `kind delete cluster` **por fuera de Terraform**, como una pérdida real. Se borraron el clúster completo (3 nodos, todos los volúmenes y todos los objetos de Kubernetes), la **copia local de la llave** de Sealed Secrets y el **kubeconfig**. Sobrevivieron solo los repos de GitHub, MinIO (estado, respaldos y llave) y `~/.sa-p9/minio.env`.
3. **Reconstrucción** (`bootstrap.sh`), sin ningún paso manual intermedio.

## 3. Tiempos medidos (RTO)

| Marca (log) | Hora | Desde el desastre | Fase |
|---|---|---:|---|
| `DESTRUCCION_INICIO` | 07:35:10 | 0 s | inicio del desastre |
| `INICIO_BOOTSTRAP` | 07:35:20 | 10 s | clúster ya no existe |
| `TERRAFORM_APPLY_INICIO` | 07:35:38 | 28 s | MinIO arriba y llave descargada (18 s) |
| `TERRAFORM_APPLY_FIN` | 07:38:38 | 208 s | kind + StorageClass + RBAC + llave + ArgoCD + raíz (**180 s**) |
| `ARGOCD_CONVERGIO` | 07:46:01 | 651 s | 8 Applications `Synced/Healthy` (**441 s**, 58 % del total) |
| `RESTAURACION_DATOS_INICIO` → `FIN` | 07:46:04 → 07:47:16 | 726 s | Velero restaura Postgres (**72 s**) |
| `FIN_BOOTSTRAP` | 07:47:51 | **761 s** | verificación: secretos, `/health` y huella de datos |

**RTO real: 761 s = 12 min 41 s.** Se mide hasta el servicio **verificado**
(secretos descifrados, `api-gateway /health → ok`, datos con la huella
correcta), no hasta que termina Terraform.

## 4. Pérdida medida (RPO)

**RPO real: 86 s** (destrucción a las 07:35:10 menos inicio del último respaldo a las 07:33:44).

- **Recuperado:** las 70 filas del respaldo, con huella idéntica (`08584b8b…`). Se compara el contenido, no el conteo.
- **No recuperado:** las **5 filas `post-respaldo`** (0 de 5 volvieron). Se escribieron después del último respaldo, así que no estaban en ninguna copia. Es el comportamiento correcto y es exactamente el RPO.
- **También se pierde** (no se midió): los mensajes en tránsito en RabbitMQ y los objetos que solo existían en el clúster, como el historial de `AnalysisRun` del canary y los `Restore` previos.

## 5. Puntos únicos de fallo detectados

| # | Punto único de fallo | Cómo apareció |
|---|---|---|
| 1 | **MinIO y `minio.env` viven en la misma máquina que el clúster.** El plan sobrevive a perder el clúster, **no a perder el host**. | Análisis del escenario: lo único que sobrevivió fue lo que estaba en ese mismo disco. |
| 2 | **Postgres: 1 réplica con volumen `local`** atado a un nodo. Si ese nodo cae, la base queda `Pending`. | La prueba de nodo drena a propósito el otro worker. El verificador lo descuenta (2.5). |
| 3 | **RabbitMQ: 1 réplica**, y su volumen se copia en caliente (no es consistente). | Revisión de las cargas con 1 réplica. |
| 4 | **Dependencia de internet**: GitHub, ghcr.io, Docker Hub y repos de Helm. 58 % del RTO fue esperar a ArgoCD, sobre todo descargando imágenes. | Desglose de tiempos de la sección 3. |
| 5 | **Pods en `Unknown` tras reiniciar la máquina.** `postgres-0` no se reconcilió solo y todos los servicios quedaron en CrashLoop. | Hallado el 2026-10-17 antes de la prueba; corregido a mano (runbook §6). |
| 6 | **El bootstrap restauraba datos sobre un clúster sano** y borraba lo escrito desde el último respaldo. | Hallado al revisar la idempotencia. **Corregido:** solo restaura si el clúster es nuevo (`CLUSTER_NUEVO`). |
| 7 | **Anti-afinidad preferida:** tras un drenaje las réplicas no se reparten de vuelta y todo queda en un nodo. | Visto el 2026-10-17: todas las réplicas estaban en `sa-p9-worker2`. |

## 6. Brecha y plan

| | Declarado | Medido | Brecha |
|---|---:|---:|---|
| RTO | 30 min | **12 min 41 s** | Se cumple con 17 min de margen. |
| RPO | 60 min | **86 s** | Se cumple, pero **86 s es un caso, no el peor**. |

**Análisis honesto:** el RTO medido es una sola corrida, con buena conexión e imágenes que kind descarga en cada nodo nuevo. Con la red lenta o con un registry caído, la fase de ArgoCD (441 s) crece sin límite, y el diseño no tiene protección contra eso. El RPO medido es bajo **solo porque la prueba tomó el respaldo 86 s antes del desastre**. Un desastre real a las HH:59 perdería casi una hora. Ese peor caso **no se probó**; está justificado por el cron, pero no medido. Los objetivos se cumplen **para el escenario probado**, que es la pérdida del clúster. El escenario más probable en una máquina personal, que es perder el host (punto 1), hoy no tiene recuperación.

**Qué haría para cerrarla, en orden de impacto:**
1. **Replicar los buckets fuera del host** (`mc mirror` programado o replicación de MinIO hacia otro servidor o un S3 real) y guardar `minio.env` en un gestor de secretos. Cierra el punto 1, el único que hoy hace imposible recuperar.
2. **Archivado continuo del WAL de Postgres** (o un operador como CloudNativePG con backups al bucket). Baja el RPO de 60 min a segundos sin respaldar el volumen cada minuto, y permite réplicas que cierran el punto 2.
3. **Caché local de imágenes** (registry espejo en la red `kind`). Reduce la fase de 441 s y quita la dependencia de internet del RTO.
4. **Probar el peor caso del RPO**: provocar el desastre justo antes del respaldo horario y medirlo, en lugar de declararlo.
