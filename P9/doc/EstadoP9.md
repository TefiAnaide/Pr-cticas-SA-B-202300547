# Estado de la Práctica 9 — qué funciona, qué no y por qué

Corte: **2026-10-17, 05:05**. El verificador oficial (`P9/verificar_p9.sh` v1.0,
hash `367900de0c69946a`) se corrió contra el clúster `kind-sa-p9` y contra lo
que hay **en GitHub** en ese momento: clona los repos, así que lo que no
tenga push no cuenta.

## Resumen

| Criterio | Oficial (05:05) | `_corregido` (05:05) | `_corregido` tras el push `7d20576` | Esperado al cerrar pendientes |
|---|---:|---:|---:|---:|
| 2.1 Bootstrap automatizado | 14 / 14 | 14 / 14 | 14 / 14 | 14 / 14 |
| 2.2 Estado remoto e IaC | 6 / 8 | 6 / 8 | **8 / 8** ✅ | 8 / 8 |
| 2.3 Respaldo con Velero | **2 / 14** ⚠️ | 14 / 14 | 14 / 14 | 14 / 14 |
| 2.4 Continuidad de secretos | 5 / 8 | 5 / 8 | 5 / 8 | **8 / 8** |
| 2.5 Resiliencia ante fallo | 6 / 8 | 6 / 8 | 6 / 8 | 6 / 8 (decisión, ver abajo) |
| 2.6 Restauración verificada | 5 / 8 | 5 / 8 | 5 / 8 | **8 / 8** |
| **Conocimiento** | **38 / 60** | **50 / 60** | **52 / 60** | **58 / 60** |
| Eliminatorios | `readme` `tfstate-en-repo` `sin-respaldo` | `readme` `tfstate-en-repo` | `readme` | ninguno |

> ⚠️ La diferencia entre la primera y la segunda columna **no es un fallo de
> la práctica**, sino un bug del verificador. Está explicado en la sección siguiente.

---

## Bug en `verificar_p9.sh` (hay que reportarlo al auxiliar)

El script usa este patrón en 7 líneas (174, 185, 194, 195, 198, 229 y 263).
`verificar_p10.sh` tiene el mismo patrón en 8 líneas:

```bash
echo "${SCHED:-{}}" | jq ...
```

La intención es "el contenido de `SCHED`, o `{}` si está vacío". Pero bash
cierra `${...}` en la **primera** `}`, así que cuando `SCHED` **sí** tiene
datos se imprime el JSON **seguido de una `}` sobrante**:

```bash
$ x='{"items":[1]}'; echo "${x:-{}}"
{"items":[1]}}
$ echo "${x:-{}}" | jq '[.items[]?] | length'; echo "exit=$?"
jq: parse error: Unmatched '}' at line 1, column 14
1
exit=5
```

jq imprime el resultado, falla por la `}` y entonces el `|| echo 0` del
script agrega un `0`. La variable termina valiendo `"1\n0"`, la comparación
`[ "1\n0" -ge 1 ]` revienta (`se esperaba una expresión entera`) y la
comprobación cuenta como FALLA. Los `jq -e` del mismo patrón fallan siempre.

**Efecto:** cualquier estudiante que **sí** tenga Velero funcionando pierde
hasta 18 puntos (2.3 completo menos la instalación, la comprobación de
`kube-system` en 2.4 y la de restauraciones en 2.6) y recibe el eliminatorio
falso `sin-respaldo`. Con jq 1.7.1 (el de esta máquina) se reproduce siempre.

**Corrección:** una sola sustitución, `"${VAR:-{}}"` → `"${VAR:-"{}"}"`.
Con `"{}"` entre comillas la expansión cierra donde debe: vacía da `{}` y
con datos da el JSON intacto.

El auxiliar autorizó modificar los scripts **indicando qué, dónde y por
qué**, así que se dejaron copias aparte y los originales quedan intactos
(su hash coincide con el publicado):

| Archivo | Qué es |
|---|---|
| `P9/verificar_p9.sh` | Original, sin tocar (sha256 `367900de…`) |
| `P9/verificar_p9_corregido.sh` | Copia con la corrección en las 7 líneas y `VERSION="1.0-fix1"` |
| `P10/verificar_p10.sh` | Original, sin tocar (sha256 `0f423f01…`) |
| `P10/verificar_p10_corregido.sh` | Copia con la corrección en las 8 líneas y `VERSION="1.0-fix1"` |

Cada copia tiene al inicio un bloque con el hash del original, las líneas
exactas, el porqué y el ejemplo que lo reproduce. `diff` entre original y
copia muestra solo el bloque, `VERSION` y esas líneas. Con la copia, 2.3 da
14/14 con los mismos datos: 116 respaldos `Completed`, Schedule con ttl,
destino MinIO `Available` y File System Backup de volúmenes.

---

## Lo que funciona

| Componente | Evidencia | Por qué funciona |
|---|---|---|
| **Bootstrap de un solo comando** | 2.1 = 14/14; `sa-p9-root` con 7 hijas `Synced` | `P9/bootstrap.sh` → MinIO → llave → Terraform (kind, StorageClass, RBAC, llave, ArgoCD, app raíz) → ArgoCD por sync-waves → restauración → verificación. Sin pasos manuales intermedios. |
| **Estado remoto con bloqueo** | `backend "s3"` en MinIO con `use_lockfile`; `evidencias/bloqueo-estado-remoto.log` muestra el segundo `plan` rechazado con `412 PreconditionFailed` | MinIO es compatible con S3 y soporta la escritura condicional (`If-None-Match`) que usa `use_lockfile`. No hace falta AWS ni DynamoDB. |
| **Respaldos programados** | Schedule `velero-sa-p8-cada-hora` (`0 * * * *`, ttl 168h); 116 respaldos `Completed` | Velero con el plugin AWS apuntando a MinIO (`s3Url`), File System Backup con kopia. |
| **Volúmenes incluidos** | `defaultVolumesToFsBackup: true`; restore con huella sha256 idéntica | La StorageClass `local-respaldable` crea PVs tipo `local` en lugar de `hostPath`: **Velero omite los hostPath**, por eso hizo falta crearla. |
| **Almacenamiento fuera del clúster** | BSL `default` en `Available`, bucket `sa-p9-velero` | MinIO corre como contenedor Docker en la red `kind`, no dentro del clúster: `kind delete cluster` no lo toca. |
| **Restauración de datos verificada** | `evidencias/restauracion-datos-20260926-075749.log`: 50/50 filas, huella idéntica, RPO medido **148 s**, 5 filas perdidas a propósito | `restaurar-datos.sh` pausa ArgoCD (si no, `selfHeal` recrearía Postgres con disco vacío) y restaura StatefulSet + pod + PVC + PV. |
| **Pérdida de nodo** | `evidencias/perdida-nodo-20260926-083729.log`: 50 peticiones, 0 fallidas, 100 % | 2 réplicas por servicio sin estado + PDB `minAvailable: 1` + anti-afinidad preferida del api-gateway. |
| **Continuidad de la llave** | `respaldar-llave.sh` → `s3://sa-p9-llaves`; Terraform la inyecta antes de instalar el controlador | El controlador de Sealed Secrets usa una llave existente con label `active` en vez de generar una nueva. |
| **Flujo de la P8** | Apps `argo-rollouts`, `kyverno`, `politicas-kyverno` `Synced/Healthy`; Rollout `api-gateway` con AnalysisTemplate | Las mismas piezas de la P8, ahora instaladas por el app-of-apps en vez de a mano. |

## Lo que no funciona (o no puntúa) y por qué

| # | Qué | Puntos | Por qué | Estado |
|---|---|---:|---|---|
| 1 | **Falta `P9/README.md`** (eliminatorio `readme`) | — | No existía todavía. | Se escribe cuando estén los tiempos medidos de la reconstrucción. |
| 2 | **`P8/terraform/terraform.tfstate` versionado** (eliminatorio `tfstate-en-repo`) | 2.2: −2 | Se subió en el commit `b3f716d P8`. El verificador busca `*.tfstate*` en **todo** el repo, no solo en `/P9`. | ✅ Resuelto en `7d20576` (`git rm --cached`; el archivo sigue en disco). Falta subir el `.gitignore` de la raíz para que no vuelva a entrar. |
| 3 | **El respaldo no cubre `kube-system`** | 2.4: −3 | El Schedule solo respalda `sa-p8`. La llave tenía respaldo (bucket `sa-p9-llaves`), pero el verificador exige un **Backup de Velero** que incluya el namespace de la llave. | ✅ Schedule `velero-sealed-secrets-llave` agregado en GitOps (commit `d0bb9f2`). **Falta push.** Al sincronizar corre de inmediato. |
| 4 | **Ningún `Restore` en el clúster** | 2.6: −3 | El clúster actual se creó el 2026-09-27, después de las pruebas del 26. Los objetos `Restore` viven en el clúster, no en MinIO: se perdieron con él. | Se resuelve con la reconstrucción cronometrada (el bootstrap restaura y crea un `Restore`). |
| 5 | **Postgres, RabbitMQ y `reportes-service-consumer` con 1 réplica** | 2.5: −2 | El verificador exige ≥ 2 réplicas en **toda** carga del namespace. Replicar Postgres implica `architecture: replication` en el chart, que renombra el pod y el PVC (`postgres-primary-0`) y rompe `restaurar-datos.sh`, la prueba de datos y la sonda. | **Decisión: no se cambia.** Se declara como punto único de fallo en el informe de DR (la rúbrica 1.2 premia identificarlo). Se pierden 2 pts. |
| 6 | **No hay reconstrucción cronometrada** | 2.1 en la demo, 1.2 | No existe `evidencias/reconstruccion-*.log`: nunca se corrió `destruir.sh` + `bootstrap.sh` con el sistema completo. | Pendiente: requiere el push de GitOps primero. |
| 7 | **El contexto por defecto de kubectl está vacío** | todos (`sin-cluster`) | Terraform escribe el kubeconfig en `~/.kube/sa-p9.config`, no en `~/.kube/config`. El verificador usa el contexto actual. | Antes de calificar: `export KUBECONFIG=~/.kube/sa-p9.config` (anotado en `p9.conf`). |
| 8 | **`postgres-0` quedó en `Unknown` tras reiniciar la máquina** | requisito 8.1 "sistema operativo" | Al reiniciar el host, kind recrea los nodos pero el pod no se reconcilia; los servicios que dependen de Postgres entran en CrashLoop. | ✅ Arreglado el 2026-10-17 borrando el pod (el PVC se conserva). Documentado en el runbook §6. **Revisar el día de la calificación.** |
| 9 | **Réplicas amontonadas en `sa-p9-worker2`** | ninguno directo | La anti-afinidad es *preferida*: tras el drenaje del 26-09, las réplicas desalojadas fueron al otro worker y nunca volvieron. Hoy un drenaje de `worker2` sí cortaría el servicio. | Se corrige solo con la reconstrucción (pods nuevos se reparten). Si no, `kubectl rollout restart deploy -n sa-p8`. |
| 10 | **`[AVISO] El bootstrap menciona pasos manuales`** | 0 | El grep encuentra la palabra "manual" en el comentario *"sin pasos **manual**es intermedios"*. Falso positivo. | No requiere cambio; explicarlo si lo preguntan. |

## Pruebas que fallaron antes y por qué (se conservan como evidencia)

| Log | Qué pasó | Qué se corrigió |
|---|---|---|
| `restauracion-datos-20260926-072243-FALLIDA.log` | `postgres-0` nunca quedó Ready (timeout de 29 min) y el contenido no coincidía. El PVC restaurado apuntaba al PV borrado. | `restaurar-datos.sh` incluye ahora `persistentvolumes` en el restore: Velero detecta que los datos vienen del File System Backup y limpia `spec.volumeName` para aprovisionar un PV nuevo. |
| `perdida-nodo-20260926-080414-FALLIDA.log` | El drenaje no terminaba: `Cannot evict pod as it would violate the pod's disruption budget`. | Los servicios tenían 1 réplica con PDB `minAvailable: 1`, así que nunca se podían desalojar. Se subieron a 2 (`chart/values-p9.yaml`). La disponibilidad fue 100 % igualmente: el gateway sí tenía 2. |

## Pendientes, en orden

- [ ] **Push del repo GitOps** (`d0bb9f2`): sin esto no hay respaldo de `kube-system` y la reconstrucción no lo incluye.
- [x] Push del repo de código (`7d20576`): borrado del tfstate de P8, `bootstrap.sh`, `p9.conf`, `doc/`.
- [ ] Commit del `.gitignore` de la raíz y de `verificar_p9_corregido.sh` / `verificar_p10_corregido.sh`.
- [ ] Respaldo de referencia con filas marcadas → `destruir.sh` → `bootstrap.sh` (RTO real).
- [ ] Prueba de pérdida de nodo sobre el clúster reconstruido (las réplicas quedan repartidas).
- [ ] Informe de DR (`doc/InformeDR.md`) con los seis campos y los tiempos reales.
- [ ] `P9/README.md` con la tabla 4.1 completa.
- [ ] Preguntas teóricas (`doc/PreguntasTeoricas.md`) para preparar la defensa.
- [ ] Video de 5 a 8 minutos y su minutaje en el README.
- [x] Copias corregidas y documentadas de los verificadores (P9 y P10).
- [ ] Avisar al auxiliar que se usa `verificar_p9_corregido.sh` y por qué.
- [ ] El día de la calificación: encender MinIO y el clúster, revisar que no haya pods en `Unknown` (runbook §6) y exportar `KUBECONFIG`.
