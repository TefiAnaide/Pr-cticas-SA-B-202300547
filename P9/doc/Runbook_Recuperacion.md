# Runbook de recuperación — Práctica 9

Procedimiento para recuperar la plataforma `sa-p8` (microservicios de las
prácticas 5 a 8) sin ayuda de quien la construyó. Cada paso dice **qué
correr**, **qué se debe ver** y **qué hacer si no se ve eso**. No se salte
la verificación de un paso: el siguiente asume que el anterior quedó bien.

Todos los comandos se corren desde la raíz del repositorio de código
(`Pr-cticas-SA-B-202300547/`) en una terminal `bash`.

---

## 0. Antes de empezar (siempre)

### 0.1 Qué escenario es

| Síntoma | Escenario | Sección |
|---|---|---|
| `kubectl get nodes` falla, el clúster `sa-p9` no existe o está irrecuperable | Pérdida total del clúster | [1](#1-pérdida-total-del-clúster) |
| La aplicación responde pero faltan datos o se borró una tabla | Pérdida de datos de Postgres | [2](#2-pérdida-de-datos-de-postgres) |
| Un nodo está `NotReady` o hay que sacarlo de servicio | Pérdida o mantenimiento de un nodo | [3](#3-pérdida-o-mantenimiento-de-un-nodo) |
| Pods en `CreateContainerConfigError`, `SealedSecret` sin `Synced=True` | Secretos que no se descifran | [4](#4-los-secretos-no-se-descifran) |
| `terraform` responde `Error acquiring the state lock` y nadie más lo está usando | Bloqueo de estado huérfano | [5](#5-bloqueo-del-estado-de-terraform-huérfano) |
| Pod de Postgres en `Unknown` tras reiniciar la máquina | Pod atascado | [6](#6-pod-atascado-en-unknown-tras-reiniciar-la-máquina) |

### 0.2 Qué tiene que sobrevivir para poder recuperar

El plan asume que **solo** sobreviven estas tres cosas. Si falta alguna,
la recuperación no es posible con este runbook (ver el informe de DR,
puntos únicos de fallo):

1. **El repositorio de código** (este) y **el repositorio GitOps**
   (`https://github.com/TefiAnaide/Practicas-SA-GitOps`), públicos en GitHub.
2. **El contenedor MinIO `sa-p9-minio`** y su volumen Docker
   `sa-p9-almacenamiento_sa-p9-minio-data`. Guarda el estado de Terraform,
   los respaldos de Velero y la llave de Sealed Secrets.
3. **El archivo `~/.sa-p9/minio.env`** (credenciales de MinIO). No está en
   ningún repositorio a propósito.

Verifique las tres:

```bash
git -C . remote -v                                  # repo de código
docker ps --filter name=sa-p9-minio --format '{{.Names}} {{.Status}}'
test -f ~/.sa-p9/minio.env && echo "credenciales OK"
```

**Debe ver:** el remoto de GitHub, `sa-p9-minio Up ...` y `credenciales OK`.
Si MinIO aparece detenido, no lo recree: `bootstrap.sh` lo levanta con el
mismo volumen. Si el **volumen** no existe (`docker volume ls | grep minio`),
los respaldos se perdieron: escale, no siga.

### 0.3 Herramientas

```bash
for t in docker kind kubectl terraform helm velero aws jq openssl; do
  command -v $t >/dev/null && echo "ok  $t" || echo "FALTA $t"; done
```

**Debe ver:** diez líneas `ok`. Terraform debe ser ≥ 1.11 (`terraform version`),
porque el bloqueo del estado usa `use_lockfile`. El CLI `aws` se usa solo
como cliente S3 contra MinIO: **no requiere cuenta de AWS**.

### 0.4 Contexto de kubectl

El kubeconfig del clúster está en `~/.kube/sa-p9.config` (lo escribe
Terraform). En **cada** terminal nueva:

```bash
export KUBECONFIG=~/.kube/sa-p9.config
```

Los scripts de `P9/` lo exportan solos. Los comandos sueltos de este
runbook no.

---

## 1. Pérdida total del clúster

**Tiempo esperado:** entre 15 y 30 minutos, casi todo esperando a que
ArgoCD sincronice y se descarguen imágenes. **No hay pasos manuales
intermedios:** un único comando reconstruye todo.

### 1.1 Reconstruir

```bash
./P9/bootstrap.sh
```

El script imprime cada fase con marcas de tiempo y deja el registro en
`P9/evidencias/reconstruccion-<fecha>.log`. Lo que hace, en orden (ver
[`DiagramaBootstrap.md`](DiagramaBootstrap.md)):

| Fase en pantalla | Qué hace | Si falla aquí |
|---|---|---|
| `== 0. Herramientas` | comprueba los binarios | instale el que diga `falta la herramienta: X` |
| `== 1. Almacenamiento externo` | `docker compose up` de MinIO, crea buckets si faltan | `docker logs sa-p9-minio`; puerto 9100 ocupado → libérelo |
| `== 2. Llave de Sealed Secrets` | baja la llave de `s3://sa-p9-llaves/sealed-secrets/` a `~/.sa-p9/sealed-secrets/` | si dice `AVISO: no hay llave respaldada`, **deténgase** (Ctrl+C) y vaya a la sección [4](#4-los-secretos-no-se-descifran) |
| `== 3. Terraform` | `init` con el backend en MinIO y `apply`: clúster kind, StorageClass, namespace/RBAC, llave, ArgoCD y la app raíz | `state locked` → sección [5](#5-bloqueo-del-estado-de-terraform-huérfano) |
| `== 4. ArgoCD sincroniza el resto` | espera a que las 8 Applications estén `Synced/Healthy` (hasta 30 min) | ver 1.3 |
| `== 5. Respaldo de la llave` | vuelve a respaldar la llave en MinIO (idempotente) | no bloquea; repítalo con `./P9/scripts/respaldar-llave.sh` |
| `== 6. Restauración de datos` | elige el último respaldo **completo de `sa-p8`** anterior al bootstrap y restaura Postgres | ver sección [2](#2-pérdida-de-datos-de-postgres), paso 2.3 |
| `== 7. Verificación final` | comprueba apps, SealedSecrets, `/health` del gateway y filas de `dr_marcas` | ver 1.2 |

### 1.2 Verificar que la recuperación terminó

Al final, el script debe imprimir **todas** estas líneas:

```
OK: todos los SealedSecrets descifrados con la llave restaurada
OK: api-gateway /health -> {...}
Filas en productos_db.dr_marcas: <número mayor que 0>
RTO MEDIDO (destruccion -> servicio restaurado y verificado): ... s
```

Compruébelo además a mano:

```bash
export KUBECONFIG=~/.kube/sa-p9.config
kubectl get applications -n argocd          # 8 filas, todas Synced + Healthy
kubectl get pods -n sa-p8                   # todos Running 1/1 (los CronJob en Completed)
kubectl get sealedsecrets -A                # columna STATUS vacía o "Synced"
velero schedule get                         # 2 schedules en Enabled
velero restore get                          # el restore de esta reconstrucción en Completed
```

`sa-p8` puede quedar `Progressing` unos minutos mientras las probes de los
servicios pasan. Si sigue así después de 10 minutos, vaya a 1.3.

### 1.3 Si ArgoCD no converge

```bash
kubectl get applications -n argocd
kubectl get application <app-con-problema> -n argocd -o jsonpath='{.status.conditions}'; echo
```

| Lo que ve | Causa probable | Acción |
|---|---|---|
| `sa-p9-root` sin hijas | el repo GitOps no es accesible | `git ls-remote https://github.com/TefiAnaide/Practicas-SA-GitOps` debe responder sin pedir usuario |
| `sa-p8` `Degraded`, pods `CreateContainerConfigError` | secretos sin descifrar | sección [4](#4-los-secretos-no-se-descifran) |
| `velero` `Degraded` | credenciales de MinIO | `kubectl get secret velero-credentials -n velero` debe existir |
| Pods `ImagePullBackOff` | sin internet o registry caído | espere y reintente; las imágenes vienen de `ghcr.io` y Docker Hub |
| Kyverno rechaza un pod (`admission webhook ... denied`) | una imagen nueva con tag `latest` o sin límites | corrija el manifiesto **en el repo GitOps**, nunca con `kubectl edit` |

Cuando corrija la causa, **vuelva a correr `./P9/bootstrap.sh`**. Es
idempotente: no destruye lo que ya está bien.

---

## 2. Pérdida de datos de Postgres

Úselo cuando la aplicación funciona pero los datos se borraron o se
corrompieron. **Restaurar sobrescribe la base actual** con el contenido
del respaldo: lo escrito después del respaldo se pierde (ese es el RPO).

### 2.1 Confirmar el daño

```bash
export KUBECONFIG=~/.kube/sa-p9.config
source P9/scripts/lib.sh
psql_pg productos_db "SELECT count(*) FROM productos"
psql_pg productos_db "SELECT etapa, count(*) FROM dr_marcas GROUP BY etapa"
```

### 2.2 Elegir el respaldo

```bash
velero backup get | grep sa-p8-cada-hora | head
```

Elija el más reciente con `STATUS = Completed` **anterior** al incidente
(la columna `CREATED` está en la hora local). Use solo respaldos
`velero-sa-p8-cada-hora-*` o `prueba-datos-*`; los
`velero-sealed-secrets-llave-*` contienen solo la llave, no datos.

### 2.3 Restaurar

```bash
./P9/scripts/restaurar-datos.sh <nombre-del-backup>
```

El script pausa la sincronización automática de ArgoCD (si no, ArgoCD
recrearía Postgres con un disco vacío antes de que Velero lo restaure),
borra el StatefulSet y el PVC de Postgres, restaura desde Velero y
reactiva ArgoCD **aunque falle** (trap `EXIT`).

**Debe ver:** `Restore restaurar-pg-<fecha> -> Completed` y
`postgres-0 Ready con los datos restaurados`.

**Si `postgres-0` no queda Ready en 5 minutos:**

```bash
kubectl describe pod postgres-0 -n sa-p8 | tail -20
velero restore describe <restore> --details
```

Si el pod queda `Pending` por el volumen, el PVC apunta a un PV
inexistente: vuelva a correr el script con el mismo backup. Si de todas
formas quedó pausado ArgoCD, reactívelo:

```bash
for a in sa-p8 sa-p9-root; do kubectl patch application $a -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'; done
```

### 2.4 Verificar el contenido (no solo que el volumen exista)

Repita las consultas de 2.1. Las filas deben coincidir con el momento del
respaldo. Para una prueba completa y medida (escribe datos, respalda,
destruye, restaura y compara la huella sha256):

```bash
./P9/scripts/prueba-restauracion-datos.sh
```

Deja `P9/evidencias/restauracion-datos-<fecha>.log` con la línea
`OK: contenido restaurado identico al del momento del respaldo` y el RPO.

---

## 3. Pérdida o mantenimiento de un nodo

Los servicios sin estado tienen 2 réplicas y un PodDisruptionBudget
`minAvailable: 1`, y el api-gateway tiene anti-afinidad por nodo.
Drenar **un** worker no corta el servicio.

### 3.1 Sacar un nodo de servicio

```bash
export KUBECONFIG=~/.kube/sa-p9.config
kubectl get pods -n sa-p8 -o wide          # anote en qué nodo está postgres-0
kubectl drain <nodo> --ignore-daemonsets --delete-emptydir-data --timeout=240s
```

**Debe ver:** `node/<nodo> drained`. Mensajes `Cannot evict pod as it would
violate the pod's disruption budget` son normales unos segundos: el PDB
espera a que la otra réplica esté lista.

**Cuidado con el nodo de `postgres-0`:** su volumen es local a ese nodo.
Si lo drena, Postgres queda `Pending` hasta que el nodo vuelva (punto
único de fallo documentado en el informe). Solo los servicios sin estado
sobreviven al drenaje.

### 3.2 Devolver el nodo

```bash
kubectl uncordon <nodo>
kubectl rollout restart deploy -n sa-p8      # opcional: repartir réplicas entre nodos
kubectl argo rollouts restart api-gateway -n sa-p8
```

### 3.3 Prueba medida

```bash
./P9/scripts/prueba-perdida-nodo.sh
```

Consulta `/health` cada segundo a través del Service mientras drena el
worker que no tiene a Postgres. Deja `P9/evidencias/perdida-nodo-<fecha>.log`
con `Peticiones: N, fallidas: 0, disponibilidad: 100.00%`.

---

## 4. Los secretos no se descifran

Síntoma: `kubectl get sealedsecrets -A` muestra `no key could decrypt
secret` y los pods quedan en `CreateContainerConfigError`. Causa: el
controlador arrancó con una llave **nueva** en lugar de la respaldada.

### 4.1 Recuperar la llave

La llave tiene dos respaldos fuera del clúster. Use el primero que exista:

**a) Bucket de llaves en MinIO** (lo escribe `respaldar-llave.sh`):

```bash
source P9/scripts/lib.sh && cargar_credenciales
s3 s3 ls s3://sa-p9-llaves/sealed-secrets/       # debe listar <nombre>.crt y <nombre>.key
s3 s3 cp s3://sa-p9-llaves/sealed-secrets/ ~/.sa-p9/sealed-secrets/ --recursive
```

**b) Respaldo de Velero** (Schedule `velero-sealed-secrets-llave`, cada 6 h):

```bash
velero backup get | grep sealed-secrets-llave | head -3
velero restore create --from-backup <backup-de-la-llave> --include-namespaces kube-system --wait
```

### 4.2 Hacer que el controlador use la llave restaurada

```bash
# Con la opción a), inyéctela con Terraform (mismo procedimiento que el bootstrap):
cd P9/terraform && terraform apply -auto-approve && cd -
# En ambos casos, reinicie el controlador para que lea la llave:
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
kubectl get sealedsecrets -A                     # deben pasar a Synced
kubectl rollout restart deploy -n sa-p8          # los pods toman los Secrets nuevos
```

### 4.3 Si no existe ninguna copia de la llave

Los SealedSecrets del repo GitOps son **irrecuperables**. Hay que volver
a generar cada secreto con su valor original, sellarlo con la llave nueva
(`kubeseal --controller-name sealed-secrets --controller-namespace kube-system`),
hacer commit en el repo GitOps y luego respaldar la llave nueva con
`./P9/scripts/respaldar-llave.sh`. Esto requiere conocer los valores en
claro: escale.

---

## 5. Bloqueo del estado de Terraform huérfano

Solo si `terraform` falla con `Error acquiring the state lock` **y está
seguro de que ningún otro `terraform` está corriendo** (un proceso
interrumpido con Ctrl+C puede dejar el lock).

```bash
source P9/scripts/lib.sh && cargar_credenciales
cd P9/terraform
terraform force-unlock <ID>        # el ID sale en el mensaje del error ("Lock Info: ID: ...")
cd -
```

Nunca borre `p9/terraform.tfstate` del bucket. El bucket tiene
versionado: si un `apply` dejó el estado corrupto, recupere una versión
anterior desde la consola de MinIO (`http://localhost:9101`, usuario y
contraseña en `~/.sa-p9/minio.env`).

---

## 6. Pod atascado en `Unknown` tras reiniciar la máquina

Al reiniciar el host, los contenedores de kind se recrean pero a veces
un pod queda en `Unknown` y los servicios que dependen de él entran en
`CrashLoopBackOff` (pasó con `postgres-0` el 2026-10-17).

```bash
export KUBECONFIG=~/.kube/sa-p9.config
kubectl get pods -n sa-p8 | grep -v Running
kubectl delete pod postgres-0 -n sa-p8 --wait=false    # el PVC se conserva
kubectl wait --for=condition=Ready pod/postgres-0 -n sa-p8 --timeout=240s
```

Los demás servicios se recuperan solos en 2 a 5 minutos, cuando sus
probes vuelven a pasar.

---

## Referencias rápidas

| Qué | Dónde |
|---|---|
| Punto de entrada | `P9/bootstrap.sh` |
| Simular la pérdida total | `P9/scripts/destruir.sh` (borra el clúster, la llave local y el kubeconfig; deja MinIO) |
| Estado de Terraform | `s3://sa-p9-tfstate/p9/terraform.tfstate` en MinIO, bloqueo `use_lockfile` |
| Respaldos | bucket `sa-p9-velero`; Schedules `velero-sa-p8-cada-hora` y `velero-sealed-secrets-llave` |
| Llave de Sealed Secrets | `s3://sa-p9-llaves/sealed-secrets/` y respaldos `velero-sealed-secrets-llave-*` |
| Consola de MinIO | `http://localhost:9101` |
| Evidencias | `P9/evidencias/` |
