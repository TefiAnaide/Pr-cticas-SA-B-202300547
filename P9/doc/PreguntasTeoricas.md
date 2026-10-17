# Preguntas teóricas — preparación para la defensa (Práctica 9)

La rúbrica (1.4) premia **analizar el comportamiento del propio sistema
ante escenarios de pérdida y reconocer sus límites**, y castiga respuestas
memorizadas o contradictorias con la evidencia. Por eso cada respuesta
apunta a algo concreto de este repositorio.

---

## 1. Conceptos aplicados a este sistema

**¿Qué es el RTO y cuál es el de este sistema?**
Es el tiempo máximo aceptable entre el desastre y el servicio restaurado.
Aquí se mide desde `DESTRUCCION_INICIO` (lo escribe `destruir.sh`) hasta
`FIN_BOOTSTRAP` con la verificación pasada, no hasta "terraform terminó".
El valor declarado y el medido están en [`InformeDR.md`](InformeDR.md).

**¿Qué es el RPO y de qué depende aquí?**
Es cuánto dato se puede perder, medido en tiempo. Aquí lo fija la
frecuencia del Schedule `velero-sa-p8-cada-hora` (`0 * * * *`): **en el
peor caso, 60 minutos** (desastre justo antes del siguiente respaldo). El
medido depende de cuándo cae el desastre: en las pruebas fue de 148 s
(restauración de datos) y lo que indica el log de la reconstrucción.
Bajarlo implica respaldar más seguido (más carga y almacenamiento) o
replicar Postgres de forma continua (WAL streaming), que este sistema no tiene.

**¿Por qué el RPO medido es mucho menor que el declarado?**
Porque en la prueba el respaldo se tomó minutos antes del desastre. El
declarado es el **peor caso** del diseño; el medido es **un caso**. Reportar
solo el medido sería engañoso.

**¿Qué se reconstruye y qué se restaura?**
- **Se reconstruye** (es código, sale de Git): clúster, ArgoCD, controladores,
  políticas, despliegues, Services, NetworkPolicies, SealedSecrets.
- **Se restaura** (es estado, sale de un respaldo): el volumen de Postgres
  (Velero), la llave de Sealed Secrets (MinIO o Velero) y el estado de
  Terraform (MinIO).
- **Se pierde de forma irreversible:** lo escrito después del último
  respaldo, los mensajes en tránsito en RabbitMQ y los objetos que solo
  existen dentro del clúster, como los `Restore` y `AnalysisRun` históricos.

---

## 2. Decisiones de diseño (por qué así y no de otra forma)

**¿Por qué el estado de Terraform en MinIO y no en el repo o en local?**
En local, solo una persona en una máquina puede reconstruir. Versionado en
Git, expone el contenido (el estado de este proyecto incluye la llave de
Sealed Secrets en claro, porque Terraform la inyecta) y no tiene bloqueo:
dos `apply` simultáneos lo corrompen. El backend `s3` con `use_lockfile`
crea `terraform.tfstate.tflock` con escritura condicional; la prueba está
en `evidencias/bloqueo-estado-remoto.log` (`412 PreconditionFailed`).

**¿Por qué MinIO y no AWS S3?**
El enunciado pide almacenamiento de objetos **externo al clúster**, no un
proveedor. MinIO habla el protocolo S3, así que Terraform, Velero y el CLI
`aws` lo usan sin cambios, sin costo y sin cuenta en la nube. El límite
honesto: corre en la **misma máquina** que el clúster (ver sección 3).

**¿Por qué el bootstrap pausa ArgoCD para restaurar?**
Con `selfHeal: true`, al borrar el StatefulSet de Postgres ArgoCD lo
recrearía en segundos **con un volumen vacío**, y Velero no restaura sobre
un recurso que ya existe. Hay que pausar la raíz y la hija (si solo se
pausa la hija, la raíz revierte el cambio).

**¿Por qué `skipImmediately: true` en el Schedule horario?**
En un clúster recién reconstruido, el primer respaldo inmediato guardaría
una **base vacía** como "el respaldo más reciente". Si el bootstrap fallara
a la mitad y se reintentara, restauraría esa base vacía. Por eso el
Schedule espera a la siguiente hora y el bootstrap ignora los respaldos
creados después de su inicio.

**¿Por qué una StorageClass propia (`local-respaldable`)?**
El `local-path` de kind crea volúmenes `hostPath`, y el File System Backup
de Velero **omite los `hostPath`**. El respaldo terminaba `Completed` pero
sin datos: el peor tipo de fallo, porque parece éxito. Con
`defaultVolumeType: local` el mismo provisionador crea PVs tipo `local`, que
sí se respaldan.

**¿Por qué anti-afinidad *preferida* y no *requerida*?**
Con 2 workers y anti-afinidad requerida, el pod extra que crea Argo
Rollouts durante un canary no tendría nodo libre y el despliegue se
bloquearía. Lo mismo al drenar: la réplica desalojada no tendría dónde ir.
El costo: tras un drenaje, las réplicas pueden quedar juntas en un nodo
(pasó aquí: todo quedó en `sa-p9-worker2`) y no se reparten solas.

**¿Por qué 2 réplicas en los servicios sin estado?**
Con 1 réplica y un PDB `minAvailable: 1`, `kubectl drain` **nunca termina**:
el PDB prohíbe desalojar la única réplica. Pasó en
`perdida-nodo-20260926-080414-FALLIDA.log`.

**¿Cómo se garantiza que la llave restaurada sea la que usa el controlador?**
Terraform crea el Secret de la llave en `kube-system` con la etiqueta
`sealedsecrets.bitnami.com/sealed-secrets-key=active` **antes** de crear la
app raíz (`depends_on` en `argocd.tf`). Cuando ArgoCD instala el
controlador (ola -3), encuentra esa llave y no genera una nueva.

---

## 3. Límites que se reconocen (puntos únicos de fallo)

**Si se pierde la máquina completa, ¿se recupera el sistema?**
**No con este diseño.** MinIO (estado, respaldos y llave) corre en la misma
máquina que el clúster, y `~/.sa-p9/minio.env` también. El plan cubre
perder el **clúster**, no el **host**. Para cubrirlo: replicar el bucket a
otro sitio (`mc mirror` o la replicación de MinIO hacia otro servidor o un
S3 real) y guardar las credenciales en un gestor de secretos externo.

**¿Qué pasa si se cae el nodo donde está Postgres?**
Postgres queda `Pending` hasta que el nodo vuelva: su volumen es `local` y
está atado a ese nodo. El servicio **de lectura y escritura** cae; solo los
servicios sin estado siguen respondiendo (por eso `prueba-perdida-nodo.sh`
drena el otro worker). Opciones: Postgres replicado (`architecture:
replication` o un operador como CloudNativePG) con almacenamiento de red.
No se hizo porque renombra pods y PVCs y rompe los procedimientos ya
probados; por la misma razón el verificador descuenta 2 puntos en 2.5.

**¿Y RabbitMQ?**
Mismo caso: 1 réplica, volumen local. Además **no se respalda la cola en
vuelo** de forma consistente: Velero copia archivos de un broker en
ejecución. Los mensajes publicados después del último respaldo se pierden.

**¿Qué pasa si GitHub no está disponible?**
ArgoCD no puede sincronizar `apps/` y el bootstrap se detiene en la fase 4.
Lo ya desplegado sigue funcionando; una reconstrucción no es posible hasta
que vuelva. Mitigación: un espejo del repo GitOps accesible desde el
clúster.

**¿Qué pasa si se pierden las dos copias de la llave?**
Los SealedSecrets del repo GitOps son irrecuperables. Hay que regenerar
cada secreto con su valor en claro y volver a sellarlo (runbook §4.3).

**¿Qué pasa si el controlador de Sealed Secrets rota la llave?**
Lo hace cada 30 días por defecto. Los secretos nuevos se sellan con la
llave nueva, que **no** está en el bucket hasta que corre
`respaldar-llave.sh`. El Schedule `velero-sealed-secrets-llave` (cada 6 h)
reduce esa ventana a 6 horas como máximo.

**¿La reconstrucción depende de internet?**
Sí: imágenes (ghcr.io, Docker Hub, quay.io), charts de Helm y el repo
GitOps. Sin red no hay reconstrucción. Parte del RTO medido es solo
descarga de imágenes.

---

## 4. Preguntas probables sobre la evidencia

**¿Cómo sabe que la restauración recuperó datos reales y no un volumen vacío?**
Por la huella sha256 de todas las filas de `dr_marcas` (id, etapa, dato y
fecha) antes del respaldo y después de restaurar: deben coincidir. Contar
filas no basta (podrían ser otras); que el PVC exista tampoco.

**¿Por qué hay logs marcados `-FALLIDA` en las evidencias?**
Porque fallaron y se conservan. La restauración falló porque el PVC
restaurado apuntaba a un PV borrado (se corrigió incluyendo
`persistentvolumes`). El drenaje falló por PDB con 1 réplica (se subieron
a 2). Borrarlos ocultaría cómo se llegó al diseño final.

**¿Qué hace exactamente `destruir.sh`?**
Borra el clúster con `kind delete cluster` (por fuera de Terraform, como
una pérdida real), la copia local de la llave y el kubeconfig. Deja MinIO.
Antes verifica que la llave esté en el bucket; si no, se niega a seguir.

**¿Por qué el bootstrap hace `terraform state rm` si el clúster no existe?**
El estado remoto todavía lista recursos que vivían dentro del clúster
perdido (namespace, Secret de la llave, releases de Helm). Terraform
intentaría refrescarlos contra un API server que ya no existe y fallaría.
Retirarlos del estado refleja la verdad: ya no existen y hay que crearlos.

**¿Es idempotente el bootstrap?**
Sí, y **no lo era al principio**. Terraform no tiene diferencias y ArgoCD
ya está sincronizado, pero la versión original **restauraba el último
respaldo aunque el clúster estuviera sano**: correrlo "por si acaso"
borraba todo lo escrito desde ese respaldo. Se detectó al preparar esta
defensa y se corrigió. Ahora el bootstrap anota si el clúster **ya
existía** (`CLUSTER_NUEVO`) y solo restaura sobre un clúster recién
creado. Para restaurar a propósito sobre uno existente (por ejemplo, tras
corromper datos) está `restaurar-datos.sh` o `FORZAR_RESTAURACION=1`. La
prueba está en `evidencias/idempotencia-*.log`: una fila escrita después
de la reconstrucción sobrevive a una segunda corrida del bootstrap.
