# Práctica 9 — Continuidad operativa y recuperación ante desastres

La plataforma de microservicios de las prácticas 5 a 8 ahora **se puede
recuperar**: un solo comando reconstruye todo desde cero, los datos y la
llave de los secretos se respaldan fuera del clúster, y se demostró
destruyendo el entorno con el cronómetro corriendo.

**Resultado de la prueba (2026-10-17):** RTO **12 min 41 s** (objetivo 30 min) ·
RPO **86 s** (objetivo 60 min) · datos restaurados con huella sha256 idéntica ·
0 peticiones fallidas al drenar un nodo.

| Documento | Contenido |
|---|---|
| [`doc/InformeDR.md`](doc/InformeDR.md) | Informe de la prueba de DR (plantilla 4.2: los seis campos) |
| [`doc/Runbook_Recuperacion.md`](doc/Runbook_Recuperacion.md) | Runbook ejecutable por un tercero: pérdida total, de datos, de nodo, de la llave, lock huérfano y pod atascado |
| [`doc/DiagramaBootstrap.md`](doc/DiagramaBootstrap.md) | Orden de reconstrucción y dependencias, automático vs. manual |
| [`doc/PreguntasTeoricas.md`](doc/PreguntasTeoricas.md) | Análisis del sistema ante escenarios de pérdida y sus límites |
| [`doc/EstadoP9.md`](doc/EstadoP9.md) | Qué funciona, qué no y por qué; puntajes del verificador |

## 4.1 Tabla de enlaces obligatoria

| Ítem | Enlace o dato requerido |
|---|---|
| Repositorio GitOps | https://github.com/TefiAnaide/Practicas-SA-GitOps |
| Aplicación raíz en ArgoCD | **`sa-p9-root`**, namespace **`argocd`** (gestiona 7 Applications hijas en [`apps/`](https://github.com/TefiAnaide/Practicas-SA-GitOps/tree/main/apps) del repo GitOps) |
| Punto de entrada del bootstrap | [`P9/bootstrap.sh`](bootstrap.sh) — se ejecuta como `./P9/bootstrap.sh` desde la raíz del repositorio |
| Backend remoto de Terraform | Tipo **`s3`** (compatible con S3: MinIO en un contenedor Docker **fuera** del clúster), bucket `sa-p9-tfstate`, key `p9/terraform.tfstate`, endpoint `http://localhost:9100`, bloqueo con `use_lockfile` (archivo `.tflock`). Bucket con versionado. Sin credenciales en el repo: se leen de `~/.sa-p9/minio.env`. Configuración en [`terraform/versions.tf`](terraform/versions.tf) |
| Schedule de Velero | **`velero-sa-p8-cada-hora`** (`0 * * * *`, ttl 168h, namespace `sa-p8` con volúmenes) y **`velero-sealed-secrets-llave`** (`30 */6 * * *`, ttl 720h, llave en `kube-system`). Destino: BackupStorageLocation `default` → bucket **`sa-p9-velero`** en MinIO (`http://sa-p9-minio:9000`). Definidos en [`apps/04-velero.yaml`](https://github.com/TefiAnaide/Practicas-SA-GitOps/blob/main/apps/04-velero.yaml) |
| Reconstrucción cronometrada | [`P9/evidencias/reconstruccion-20261017-073520.log`](evidencias/reconstruccion-20261017-073520.log) (además: [`preparacion-reconstruccion-20261017-073327.log`](evidencias/preparacion-reconstruccion-20261017-073327.log) y [`destruccion-20261017-073505.log`](evidencias/destruccion-20261017-073505.log)) |
| Restauración de datos | [`P9/evidencias/restauracion-datos-20260926-075749.log`](evidencias/restauracion-datos-20260926-075749.log) (borrado de tabla + volumen; 50/50 filas, huella idéntica) y la verificación de la reconstrucción total en [`reconstruccion-20261017-073520.log`](evidencias/reconstruccion-20261017-073520.log) (70/70 filas, huella idéntica). Restore en el clúster: `restaurar-pg-20261017-074604` |
| Prueba de pérdida de nodo | [`P9/evidencias/perdida-nodo-20261017-074950.log`](evidencias/perdida-nodo-20261017-074950.log) (drenaje de `sa-p9-worker2`: 48 peticiones, 0 fallidas, 100 %). Prueba anterior: [`perdida-nodo-20260926-083729.log`](evidencias/perdida-nodo-20260926-083729.log) |
| RTO y RPO declarados | **RTO:** objetivo **30 min** → medido **12 min 41 s** (761 s). **RPO:** objetivo **60 min** → medido **86 s** (5 filas escritas después del último respaldo, perdidas a propósito). Justificación y brecha en [`doc/InformeDR.md`](doc/InformeDR.md) |
| Video demostrativo | **No requerido**: el auxiliar indicó que esta entrega no lleva video. La demostración es presencial; el orden sugerido está abajo. |

### Orden sugerido para la demostración presencial

| Paso | Punto demostrado |
|---|---|
| 1 | Sistema sano: `kubectl get applications -n argocd` (8 `Synced/Healthy`), `velero schedule get`, `velero backup get` |
| 2 | Estado remoto: bucket `sa-p9-tfstate` en MinIO, `git ls-files \| grep tfstate` vacío, prueba de bloqueo |
| 3 | `./P9/scripts/preparar-reconstruccion.sh`: datos de referencia y respaldo |
| 4 | `./P9/scripts/destruir.sh`: el clúster desaparece (`kind get clusters`, `docker ps`) |
| 5 | `./P9/bootstrap.sh`: un solo comando, fases y sync-waves en ArgoCD (~13 min) |
| 6 | Verificación: SealedSecrets descifrados, `/health`, huella idéntica, **RTO y RPO impresos** |
| 7 | Pérdida de nodo: `./P9/scripts/prueba-perdida-nodo.sh`, 0 peticiones fallidas |
| 8 | Runbook e informe de DR: brecha y puntos únicos de fallo |

## Estructura

```
P9/
├── bootstrap.sh                      punto de entrada único
├── scripts/
│   ├── lib.sh                        constantes y funciones comunes (KUBECONFIG, MinIO, logs con marcas)
│   ├── preparar-reconstruccion.sh    datos de referencia + respaldo antes de la prueba
│   ├── destruir.sh                   simula la pérdida total (kind delete, borra llave local y kubeconfig)
│   ├── restaurar-datos.sh            restaura Postgres desde un respaldo de Velero
│   ├── respaldar-llave.sh            copia la llave de Sealed Secrets a MinIO
│   ├── prueba-restauracion-datos.sh  borra datos, restaura y compara huellas (RPO)
│   └── prueba-perdida-nodo.sh        drena un worker con sondeo de /health cada segundo
├── terraform/                        clúster kind, StorageClass, namespace/RBAC, llave, ArgoCD, app raíz
├── minio/docker-compose.yml          almacenamiento de objetos fuera del clúster
├── evidencias/                       registros con marcas de tiempo (incluye las pruebas FALLIDAS)
├── doc/                              informe, runbook, diagrama, preguntas, estado
├── verificar_p9.sh                   verificador oficial, sin modificar
├── verificar_p9_corregido.sh         copia con un bug de bash corregido (ver abajo)
└── p9.conf                           datos de esta entrega para el verificador
```

## Cómo reproducir

```bash
# Reconstrucción completa cronometrada (asume MinIO y ~/.sa-p9/minio.env presentes)
./P9/scripts/preparar-reconstruccion.sh && ./P9/scripts/destruir.sh && ./P9/bootstrap.sh

# Verificador (usa el contexto actual de kubectl)
export KUBECONFIG=~/.kube/sa-p9.config
cd P9 && ./verificar_p9_corregido.sh
```

Requisitos: `docker kind kubectl terraform (>= 1.11) helm velero aws jq openssl`.
El CLI `aws` solo habla S3 con MinIO; **no se usa ninguna cuenta de AWS**.

## Verificador: copia corregida

`verificar_p9.sh` (v1.0, sha256 `367900de…`) tiene un error de bash:
`"${VAR:-{}}"` agrega una `}` sobrante al JSON cuando la variable **sí**
tiene datos, jq falla y el criterio cuenta como FALLA. Le quita hasta 18
puntos en 2.3, 2.4 y 2.6 a quien sí tiene Velero funcionando. Con autorización del
auxiliar, `verificar_p9_corregido.sh` cambia **solo** esas 7 líneas a
`"${VAR:-"{}"}"` y la versión a `1.0-fix1`. El encabezado de la copia
documenta qué, dónde y por qué (`diff verificar_p9.sh verificar_p9_corregido.sh`).

| | Oficial | Corregido |
|---|---:|---:|
| Conocimiento (2026-10-17, tras la reconstrucción) | 38 / 60 * | **58 / 60** |

\* Medido antes de la reconstrucción y del push del tfstate; el bug por sí solo resta 12 puntos de 2.3.
Los 2 puntos que faltan (2.5) son Postgres y RabbitMQ con 1 réplica: decisión documentada en el informe de DR (punto único de fallo #2).

## Antes de la calificación

1. MinIO arriba: `docker ps | grep sa-p9-minio`.
2. `export KUBECONFIG=~/.kube/sa-p9.config` (el contexto por defecto está vacío).
3. Ningún pod en `Unknown` tras reiniciar la máquina ([runbook §6](doc/Runbook_Recuperacion.md#6-pod-atascado-en-unknown-tras-reiniciar-la-máquina)).
4. `kubectl get applications -n argocd`: las 8 en `Synced/Healthy`.
5. `velero backup get`: al menos un respaldo `Completed`.
