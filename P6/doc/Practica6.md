# Práctica 6 — Despliegue de la plataforma en un clúster de Kubernetes en la nube

Proveedor elegido: **AWS (EKS)**, usando `eksctl` para crear el clúster
administrado (managed node group, 2 nodos). Se evaluó primero GCP/GKE, pero
la cuenta de facturación asociada a la cuenta USAC estaba cerrada (`open:
false`) y sin acceso para reactivarla; la cuenta de AWS ya estaba activa y
con control total, así que se cambió de proveedor. El enunciado permite
cualquier proveedor (3.1: "el estudiante es libre de elegir cualquier otro
proveedor: AWS (EKS)...").

- Cuenta AWS: `011528263421`
- Usuario IAM dedicado para este trabajo: `sa-p6-cli` (con `AdministratorAccess`
  temporal — se borra en la Fase 9, ver justificación ahí)
- Región: `us-east-1`
- Clúster: `sa-p6` (2 nodos `t3.medium`, nodos en subred **pública** y **sin
  NAT Gateway** — ver nota de costos en Fase 2)
- Registro: ECR, un repo por microservicio (`p6/<servicio>`)

## Índice

1. Diferencias clúster local vs. administrado (pregunta 1 del enunciado)
2. Prerrequisitos (herramientas, credenciales)
3. Fase 1 — ECR: publicar las 6 imágenes
4. Fase 2 — Crear el clúster EKS
5. Fase 3 — Adaptar el chart Helm para AWS (`values-aws.yaml`)
6. Fase 4 — Instalar `ingress-nginx` y obtener el hostname público
7. Fase 5 — Instalar la plataforma (`helm install`)
8. Fase 6 — Verificación de CronJobs (foco de la calificación)
9. Fase 7 — Evidencias (capturas, curl desde internet)
10. Fase 8 — Costos aproximados
11. Fase 9 — Eliminación de recursos
12. Respuestas a las preguntas del enunciado (3.2)
13. Pendientes

---

## 1. Diferencias clúster local vs. administrado

*(se completa en la sección 12, junto con las otras 4 preguntas — para no
responderla dos veces)*

## 2. Prerrequisitos

Ya resuelto y verificado en esta sesión:

```bash
export PATH="$HOME/.local/bin:$PATH"   # aws-cli v2 y eksctl se instalaron aqui, sin sudo

aws sts get-caller-identity
# {
#     "UserId": "AIDAQFLZDK364O6AOWPRW",
#     "Account": "011528263421",
#     "Arn": "arn:aws:iam::011528263421:user/sa-p6-cli"
# }

aws configure get region   # us-east-1

eksctl version   # 0.230.0
helm version --short
kubectl version --client
```

`kubectl` y `helm` ya estaban instalados (se usaron en la P5). `aws` y
`eksctl` se instalaron en `~/.local/bin` (agregado al `PATH` en `.bashrc`)
para no requerir `sudo`.

Autenticación: se creó un usuario IAM dedicado (`sa-p6-cli`) en vez de usar
las llaves de la cuenta root — con `AdministratorAccess` porque `eksctl`
necesita crear VPC, Security Groups, roles IAM y CloudFormation por debajo,
y acotar el policy exacto no vale la pena para un recurso que se borra al
terminar la práctica (Fase 9).

## 3. Fase 1 — ECR: publicar las 6 imágenes

Las imágenes `p5-<servicio>:runtime` ya existen en el docker local (host),
construidas en la P5 con el Dockerfile multi-stage — no hace falta
reconstruirlas, solo retaguearlas hacia ECR y hacer push. A diferencia de
Artifact Registry (un repo puede tener muchas imágenes), **ECR requiere un
repositorio por imagen**, por eso el loop crea 6 repos.

```bash
export PATH="$HOME/.local/bin:$PATH"
ACCOUNT_ID=011528263421
REGION=us-east-1
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Login de docker contra ECR
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR"

# Crear un repo por servicio, retaguear y subir
for s in api-gateway auth-service authz-service pedidos-service productos-service reportes-service; do
  aws ecr create-repository --repository-name "p6/${s}" --region "$REGION" 2>/dev/null
  docker tag "p5-${s}:runtime" "${ECR}/p6/${s}:runtime"
  docker push "${ECR}/p6/${s}:runtime"
done

# Verificar
aws ecr describe-repositories --region "$REGION" --query "repositories[].repositoryName"
```

**Evidencia — 6 repos creados, cada uno con la imagen `runtime` (tamaños en
bytes, consistentes con los medidos en la P5 sección "Comparativa de
tamaño"):**

```
p6/auth-service        runtime   63595038
p6/reportes-service     runtime  62054025
p6/authz-service        runtime  58410149
p6/pedidos-service      runtime  59996563
p6/api-gateway          runtime  62659958
p6/productos-service    runtime  61653934
```

## 4. Fase 2 — Crear el clúster EKS

```bash
export PATH="$HOME/.local/bin:$PATH"

eksctl create cluster \
  --name sa-p6 \
  --region us-east-1 \
  --nodes 2 \
  --node-type t3.medium \
  --node-private-networking=false \
  --vpc-nat-mode Disable

# kubectl ya queda apuntando al cluster nuevo automaticamente
kubectl config current-context
kubectl get nodes -o wide
```

Toma bastante más que en minikube/GKE (~15-20 min: `eksctl` crea una VPC,
subnets, Internet Gateway, Security Groups y un `CloudFormation stack` por
debajo antes de que exista el clúster).

**`--node-private-networking=false --vpc-nat-mode Disable`**: por defecto
`eksctl` crea un NAT Gateway (~US$0.045/hora + tráfico, aparte de los nodos)
para que nodos en subred privada tengan salida a internet. Como esta
práctica no necesita aislar los nodos en una subred privada (no es un
requisito de la rúbrica), se ponen directo en la subred pública y se
deshabilita el NAT — ahorra ese costo por completo. Se documenta esto
también como respuesta a la pregunta 5 (costos) en la sección 12.

**NetworkPolicy real** (equivalente a `--cni=calico` en minikube / a
`--enable-dataplane-v2` en GKE): el CNI default de AWS (`vpc-cni`) tampoco
aplica `NetworkPolicy` sin este paso extra:

```bash
aws eks update-addon \
  --cluster-name sa-p6 \
  --region us-east-1 \
  --addon-name vpc-cni \
  --resolve-conflicts OVERWRITE \
  --configuration-values '{"enableNetworkPolicy":"true"}'
```

**StorageClass para Postgres/RabbitMQ**: a diferencia de GKE (que trae una
StorageClass default lista para usar), EKS necesita el addon del driver CSI
de EBS instalado explícitamente:

```bash
# Rol IAM que el driver necesita para crear volumenes EBS
eksctl create iamserviceaccount \
  --cluster sa-p6 --region us-east-1 \
  --namespace kube-system --name ebs-csi-controller-sa \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

eksctl create addon \
  --cluster sa-p6 --region us-east-1 \
  --name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::011528263421:role/AmazonEKS_EBS_CSI_DriverRole"

# Verificar que quede una StorageClass default (gp2, la que trae EKS por defecto)
kubectl get storageclass
```

**Evidencia — clúster real levantado (~15 min), 2 nodos `Ready` en subred
pública, Kubernetes 1.34 (sobra margen para el `timeZone` de los CronJobs,
que pide ≥1.27):**

```
NAME                             STATUS   ROLES    VERSION                INTERNAL-IP      EXTERNAL-IP
ip-192-168-29-142.ec2.internal   Ready    <none>   v1.34.10-eks-cb19647   192.168.29.142   3.87.63.35
ip-192-168-37-22.ec2.internal    Ready    <none>   v1.34.10-eks-cb19647   192.168.37.22    44.222.61.27
```

`metrics-server` vino ya instalado como addon por defecto de `eksctl`
(no hace falta el paso manual que sí hizo falta en minikube).

**Bug propio encontrado**: el clúster se creó con **OIDC deshabilitado**
por defecto — sin eso, `eksctl create iamserviceaccount` (necesario para el
rol IAM del driver de EBS) no funciona. Se resolvió habilitándolo aparte:

```bash
eksctl utils associate-iam-oidc-provider --cluster sa-p6 --region us-east-1 --approve
```

**Segundo bug propio**: al instalar el addon `aws-ebs-csi-driver`, falló
con `CREATE_FAILED` / `ConfigurationConflict` porque el `ServiceAccount
ebs-csi-controller-sa` ya existía (creado por `eksctl create
iamserviceaccount` en el paso anterior) con una etiqueta
`app.kubernetes.io/managed-by` distinta a la que el addon intenta aplicar,
y el modo de resolución de conflictos por defecto aborta en vez de
sobreescribir. Se resolvió borrando el addon fallido y recreándolo con
`--force`:

```bash
aws eks delete-addon --cluster-name sa-p6 --region us-east-1 --addon-name aws-ebs-csi-driver
eksctl create addon --cluster sa-p6 --region us-east-1 --name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::011528263421:role/AmazonEKS_EBS_CSI_DriverRole" --force
```

**Tercer detalle real**: a diferencia de GKE (que marca su StorageClass
default automáticamente), la `gp2` que EKS crea por defecto **no** viene
marcada como default — si no se corrige, los PVCs de Postgres/RabbitMQ se
quedan en `Pending` (mismo síntoma que un clúster sin ninguna StorageClass
default). Se corrigió con:

```bash
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
# NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      AGE
# gp2 (default)   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   13m
```

(El provisioner que muestra es el nombre "legacy" `kubernetes.io/aws-ebs`,
pero Kubernetes lo traduce automáticamente al driver CSI de EBS ya
instalado — es el mecanismo de migración in-tree→CSI, no un provisioner
distinto compitiendo con el que se instaló.)

## 5. Fase 3 — Adaptar el chart Helm para AWS

Se reusa el chart de la P5 tal cual (`P5/charts/sa-p5/`, no se duplica) y se
agrega un `values-aws.yaml` nuevo en `P6/charts/` que solo pisa lo que
cambia por ser un proveedor distinto:

- `image.repository` de los 6 subcharts → ruta completa de ECR.
- `ingress.hosts[0].host` → se define DESPUÉS de tener el hostname del
  Load Balancer (ver Fase 4). A diferencia de GCP (que da una IP fija, y
  ahí sí hacía falta el truco de `nip.io`), AWS ya entrega un **hostname
  DNS real** (`xxxx.us-east-1.elb.amazonaws.com`), así que se usa
  directamente, sin trucos.
- Sin `storageClass` explícito: se deja vacío para que Postgres/RabbitMQ
  usen la StorageClass default de EKS (`gp2`, provisionada por el driver
  CSI de la Fase 2).
- `resourceQuota`/`limitRange`: se reusan los mismos valores de
  `values.yaml` (pensados para 2 nodos pequeños, siguen aplicando —
  `t3.medium` es 2 vCPU/4GiB, similar orden de magnitud a los `e2-medium`
  que se habían planeado para GCP).

```yaml
# P6/charts/values-aws.yaml
api-gateway:
  image:
    repository: 011528263421.dkr.ecr.us-east-1.amazonaws.com/p6/api-gateway
auth-service:
  image:
    repository: 011528263421.dkr.ecr.us-east-1.amazonaws.com/p6/auth-service
authz-service:
  image:
    repository: 011528263421.dkr.ecr.us-east-1.amazonaws.com/p6/authz-service
pedidos-service:
  image:
    repository: 011528263421.dkr.ecr.us-east-1.amazonaws.com/p6/pedidos-service
productos-service:
  image:
    repository: 011528263421.dkr.ecr.us-east-1.amazonaws.com/p6/productos-service
reportes-service:
  image:
    repository: 011528263421.dkr.ecr.us-east-1.amazonaws.com/p6/reportes-service

# se completa en la Fase 4 con el hostname real del ELB:
# ingress:
#   hosts:
#     - host: <hostname-del-elb>.us-east-1.elb.amazonaws.com
#       paths:
#         - path: /
#           pathType: Prefix
```

> Pendiente: crear el archivo de verdad (ya con las rutas de ECR reales
> confirmadas en la Fase 1).

## 6. Fase 4 — Instalar `ingress-nginx` y obtener el hostname público

Igual que en minikube/GCP, se deja `ingressClassName: nginx` en el chart de
la P5 sin cambios — solo se instala el controller de nginx vía Helm, y AWS
le asigna automáticamente un Load Balancer con hostname público real al
`Service` tipo `LoadBalancer` que crea.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# Esperar a que el Service tenga EXTERNAL-IP (aqui sale un hostname, no una IP)
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
```

Con el hostname del ELB ya asignado, se completa `values-aws.yaml` de la
Fase 3 con ese host tal cual (sin necesidad de `nip.io`: AWS ya da un
nombre DNS resoluble públicamente).

**Evidencia — hostname real asignado por AWS:**

```
a2a8822c91c084900ad76b89688d8b9c-1586103331.us-east-1.elb.amazonaws.com
```

Ya completado en `P6/charts/values-aws.yaml`, sin ningún truco de `nip.io`
(AWS ya entrega un nombre DNS público resoluble directo).

## 7. Fase 5 — Instalar la plataforma

Mismo patrón de `-f` en cascada que en la P5, agregando `values-aws.yaml` al
final y reusando los secretos reales que ya existen en
`P5/charts/sa-p5/values.local.yaml` (nunca se versionan):

```bash
cd P5/charts/sa-p5
helm dependency update

helm install sa-p5 . \
  --namespace sa-p5 --create-namespace \
  -f values.yaml \
  -f ../../../P6/charts/values-aws.yaml \
  -f values.local.yaml

kubectl get pods,svc,ingress,pvc -n sa-p5
```

**Evidencia — instalación real en el clúster EKS, revisión 1:**

```
NAME                                             READY   STATUS    RESTARTS
api-gateway-b5bdf6c6f-p42mt                      1/1     Running   0
auth-service-6dcff84c-78tkb                      1/1     Running   0
authz-service-79bcbd546d-75r9b                   1/1     Running   0
pedidos-service-99c6454c4-wrbn7                  1/1     Running   0
postgres-0                                       1/1     Running   0
productos-service-b5dd64855-sm79x                1/1     Running   0
rabbitmq-0                                       1/1     Running   0
reportes-service-66f89f46cb-2b84q                1/1     Running   0
reportes-service-consumer-6959c777dc-67fcb       1/1     Running   2 (autorecuperado)

persistentvolumeclaim/data-postgres-0   Bound   1Gi   gp2
persistentvolumeclaim/data-rabbitmq-0   Bound   8Gi   gp2
```

Los PVC quedaron `Bound` de verdad sobre `gp2` (confirma que el driver CSI
de EBS de la Fase 2 sí está provisionando volúmenes reales).

**Nota (no es un bug de AWS)**: `reportes-service-consumer` tuvo 2 reinicios
automáticos al arrancar — mismo patrón ya documentado en
`P5/doc/Practica5.md` sección 10.4: con los 9 pods arrancando en paralelo,
RabbitMQ todavía no estaba listo cuando el consumer intentó conectar por
primera vez (`pika.exceptions.AMQPConnectionError`). Se autorecuperó solo
vía `restartPolicy: Always` y quedó estable — no requirió intervención.

## 8. Fase 6 — Verificación de CronJobs (esto es lo que más va a revisar el auxiliar)

```bash
export PATH="$HOME/.local/bin:$PATH"

# Que existan y estén activos, con su schedule real
kubectl get cronjobs -n sa-p5

# Confirmar que efectivamente se disparan solos (esperar a que pase un ciclo)
kubectl get jobs -n sa-p5 --watch

# Logs del último heartbeat y del último resumen ya ejecutados
kubectl logs -n sa-p5 -l app.kubernetes.io/component=cronjob-heartbeat --tail=20
kubectl logs -n sa-p5 -l app.kubernetes.io/component=cronjob-resumen --tail=20

# Confirmar el timezone real que está usando el CronJob (America/Guatemala)
kubectl get cronjob reportes-service-cronjob-heartbeat -n sa-p5 -o jsonpath='{.spec.timeZone}'
```

Puntos a los que hay que prestar atención (ya resueltos conceptualmente en
la P5, pero son justo lo que puede fallar al cambiar de proveedor):
- Que el Job pueda **descargar la imagen** desde ECR (si sale
  `ImagePullBackOff`, revisar que el rol IAM del node group tenga
  `AmazonEC2ContainerRegistryReadOnly` — `eksctl` lo adjunta por defecto al
  crear el managed node group, pero se verifica).
- Que siga llegando a Postgres/RabbitMQ (mismas `NetworkPolicy` de la P5,
  ahora aplicadas por el VPC CNI con `enableNetworkPolicy` en vez de
  Calico/Dataplane V2).

**Evidencia real — CronJobs corriendo solos en EKS, con el timezone correcto:**

```
NAME                                 SCHEDULE       TIMEZONE            ACTIVE   LAST SCHEDULE
reportes-service-cronjob-heartbeat   */2 * * * *    America/Guatemala   0        59s
reportes-service-cronjob-resumen     */10 * * * *   America/Guatemala   0        <none>
```

El heartbeat ya se había disparado solo dos veces antes de revisar (schedule
real funcionando, sin intervención):

```
[cronjob-heartbeat] insertado: carne=202300547 fecha_hora=2026-09-05 07:56:06.058358
[cronjob-heartbeat] insertado: carne=202300547 fecha_hora=2026-09-05 07:58:04.654223
```

Para no esperar los 10 minutos completos del segundo CronJob, se disparó
manualmente (`kubectl create job --from=cronjob/...`) para confirmar la
cadena asíncrona completa de punta a punta, igual que en la P5:

```
# cronjob-resumen -> Postgres -> RabbitMQ:
[cronjob-resumen] publicado en 'resumenes-cronjob': {"generado_en": "2026-09-05T07:59:28...", ...}

# consumer -> RabbitMQ -> Postgres:
[consumer-resumenes] guardado 94b8f5e3-af5a-4a23-b0c1-be13cef89846: {...}
```

Cadena confirmada: **heartbeat → Postgres → resumen → RabbitMQ → consumer →
Postgres**, funcionando igual que en minikube pero contra infraestructura
real de AWS. El Job manual se borró después (`kubectl delete job
resumen-manual-p6 -n sa-p5`) para no dejarlo como ruido en la demo.

Sin `ImagePullBackOff` en ningún momento — confirma que el rol IAM del
managed node group (adjuntado automáticamente por `eksctl`) sí tiene permiso
de leer los 6 repos de ECR.

## 9. Fase 7 — Evidencias

- [ ] Captura de la consola de AWS: clúster `sa-p6` en EKS. *(pendiente —
      tomar en el momento de la calificación, sobre el clúster recién
      recreado)*
- [ ] Captura de la consola de AWS: las 6 imágenes publicadas en ECR.
      *(pendiente — las imágenes en sí ya están subidas y verificadas por
      CLI, sección 3)*
- [x] `kubectl get pods -n sa-p5` con todo en `Running` (sección 7).
- [x] `curl` real desde esta máquina (red normal, no localhost/minikube)
      contra el hostname del ELB:
      ```
      $ curl -s -o /dev/null -w "HTTP %{http_code}\n" http://a2a8822c91c084900ad76b89688d8b9c-1586103331.us-east-1.elb.amazonaws.com/health
      HTTP 200
      $ curl -s -L -o /dev/null -w "HTTP final: %{http_code}\n" http://a2a8822c91c084900ad76b89688d8b9c-1586103331.us-east-1.elb.amazonaws.com/api/docs
      HTTP final: 200
      ```
- [x] Evidencia de CronJobs corriendo (sección 8).

**Nota importante**: el ELB/hostname de este run se destruirá en la Fase 9
(dry-run de hoy). El día de la calificación, al recrear el clúster desde
cero, AWS asignará un **hostname nuevo** — hay que repetir la Fase 4 para
capturarlo y volver a completar `values-aws.yaml` antes del `helm install`
de ese día. Las capturas de consola (checkboxes pendientes arriba) también
se toman ese día, sobre el clúster real de la calificación, no sobre este
dry-run.

## 10. Fase 8 — Costos aproximados

*(se calcula con precios reales de `us-east-1` una vez se sepa cuánto tiempo
estuvo arriba el clúster)*

- **Control plane EKS**: US$0.10/hora fijo (a diferencia de GKE, AWS no
  exime ningún clúster — este costo es inevitable mientras el clúster
  exista, incluso apagado no se puede "pausar").
- **Nodos**: 2 × `t3.medium` (~US$0.0416/hora c/u on-demand) → ~US$0.083/hora.
- **NAT Gateway**: **US$0 — deshabilitado a propósito** (`--vpc-nat-mode
  Disable`, ver Fase 2). Es el costo que más se pasa por alto en AWS
  (~US$0.045/hora + US$0.045/GB de tráfico) y no hacía falta para esta
  práctica.
- **Load Balancer** (del Service de `ingress-nginx`): ~US$0.025/hora + LCU.
- **EBS** (Postgres + RabbitMQ, volúmenes `gp2` pequeños): costo marginal
  por las pocas horas que dure la práctica.

> Pendiente: costo real una vez eliminado todo, usando **Billing → Cost
> Explorer** filtrado por el rango de fechas de la práctica.

## 11. Fase 9 — Eliminación de recursos

**Orden recomendado** (de adentro hacia afuera, para no dejar recursos
huérfanos facturando — sobre todo el control plane de EKS, que cobra por
hora aunque no tenga nodos):

```bash
export PATH="$HOME/.local/bin:$PATH"

# 1. Desinstalar la plataforma (borra Deployments/Services/PVCs del namespace)
helm uninstall sa-p5 -n sa-p5
helm uninstall ingress-nginx -n ingress-nginx

# 2. Confirmar que no quedaron PVs huerfanos (los volumenes EBS se pagan aparte
#    incluso si el PVC que los pidio ya no existe)
kubectl get pvc,pv -A
aws ec2 describe-volumes --region us-east-1 --filters Name=status,Values=available

# 3. Borrar el cluster completo (tambien borra el node group, VPC, etc. creados por eksctl)
eksctl delete cluster --name sa-p6 --region us-east-1

# 4. Borrar los repos de ECR (y las imagenes que contienen)
for s in api-gateway auth-service authz-service pedidos-service productos-service reportes-service; do
  aws ecr delete-repository --repository-name "p6/${s}" --region us-east-1 --force
done

# 5. Borrar el usuario IAM temporal creado para esta practica
aws iam list-access-keys --user-name sa-p6-cli
aws iam delete-access-key --user-name sa-p6-cli --access-key-id <ACCESS_KEY_ID_DEL_PASO_ANTERIOR>
aws iam detach-user-policy --user-name sa-p6-cli --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-user --user-name sa-p6-cli

# 6. Confirmar que no queda nada facturando
eksctl get cluster --region us-east-1
aws ec2 describe-volumes --region us-east-1 --filters Name=status,Values=available
aws elb describe-load-balancers --region us-east-1
```

### Dry-run de hoy (2026-09-05): se probó todo y se destruyó a propósito

Siguiendo el mismo plan ("levantarlo, comprobar que sirve, tirarlo, y para
la calificación solo repetir lo ya comprobado"), se ejecutaron las Fases 1-8
completas contra AWS real, y luego se destruyó **solo lo que cobra por
hora** — clúster, node group, Load Balancer. Se dejó a propósito:

- Los **6 repos de ECR** con las imágenes ya subidas (cobran por
  almacenamiento, centavos al mes, no por hora — así el día de la
  calificación no hay que resubir ~350MB de imágenes).
- El **usuario IAM `sa-p6-cli`** (no cuesta nada mientras no se use).

Pasos reales ejecutados:

```bash
helm uninstall sa-p5 -n sa-p5
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace sa-p5           # fuerza el borrado real de los PVC/EBS de Postgres y RabbitMQ
kubectl delete namespace ingress-nginx
eksctl delete cluster --name sa-p6 --region us-east-1
```

**Detalle real**: `eksctl delete cluster` borra el control plane de forma
**asíncrona** — el comando termina ("all cluster resources were deleted")
antes de que el clúster desaparezca de verdad. Se confirmó con
`aws eks describe-cluster --name sa-p6` hasta que devolvió
`ResourceNotFoundException` (tardó unos minutos más después de que el
comando ya había terminado).

**Verificación final — nada quedó facturando:**

```
$ eksctl get cluster --region us-east-1
No clusters found

$ aws ec2 describe-instances --region us-east-1 --filters Name=instance-state-name,Values=running,pending,stopping,stopped
(vacío)

$ aws ec2 describe-volumes --region us-east-1
(vacío)

$ aws elbv2 describe-load-balancers --region us-east-1
(vacío)
$ aws elb describe-load-balancers --region us-east-1
(vacío)

$ aws ec2 describe-nat-gateways --region us-east-1 --filter Name=state,Values=available,pending
(vacío)

$ aws ec2 describe-addresses --region us-east-1
(vacío)
```

(Se encontró una VPC no-default en la cuenta, pero pertenece a otro
proyecto ajeno a esta práctica — `practica1-g10-vpc`, tag `Gestion:
Terraform` — no algo dejado por `eksctl`.)

### Cambio de plan: se deja corriendo (no se destruye tras el dry-run)

La calificación quedó a solo horas de distancia, así que ya no compensa
destruir y volver a levantar bajo presión de tiempo. Se recreó el clúster
inmediatamente después del dry-run con el mismo procedimiento (Fases 2-7,
ya comprobado arriba) y esta vez se deja corriendo hasta después de la
calificación. Costo estimado de tenerlo arriba de más (ver Fase 8): apenas
centavos por cada hora extra, compensa el riesgo de que algo falle al
recrearlo en el momento.

**Importante**: no olvidar la Fase 9 completa (esta vez sí, incluyendo ECR
y el usuario IAM) apenas termine la calificación — el control plane de EKS
sigue cobrando US$0.10/hora aunque nadie lo esté usando.

**Estado actual (activo, este es el ambiente real de la calificación):**

```
$ kubectl get pods,pvc -n sa-p5
# 9/9 pods 1/1 Running (mismo patron de 2 reinicios auto-recuperados en
# pedidos-service/consumer por el cold-start simultaneo, ya documentado)
# data-postgres-0 y data-rabbitmq-0: Bound, gp2

$ curl -s -o /dev/null -w "HTTP %{http_code}\n" http://a36ce9884ec5b46459e7e3484015a1c2-2002816833.us-east-1.elb.amazonaws.com/health
HTTP 200

$ kubectl get cronjobs -n sa-p5
reportes-service-cronjob-heartbeat   */2 * * * *    America/Guatemala   False   0   43s
reportes-service-cronjob-resumen     */10 * * * *   America/Guatemala   False   0   <none>
```

Hostname público vigente para la demo:
`a36ce9884ec5b46459e7e3484015a1c2-2002816833.us-east-1.elb.amazonaws.com`
(distinto al del dry-run de hoy más temprano — confirma que sí hay que
recapturarlo cada vez que se recrea el `Service` de `ingress-nginx`).

**Nota práctica**: `kubectl`/`aws`/`eksctl` están instalados en
`~/.local/bin`, que no se carga automático en cada terminal nueva — hay que
exportar el PATH primero (o abrir una terminal nueva después de que
`.bashrc` ya lo tenga agregado):
```bash
export PATH="$HOME/.local/bin:$PATH"
```
Sin esto, `kubectl` falla con `exec: executable aws not found` (usa `aws
eks get-token` como plugin de credenciales por debajo).

**Evidencia — ambos CronJobs disparándose solos, en su ciclo natural (sin
intervención manual esta vez):**

```
NAME                                          STATUS     COMPLETIONS   DURATION   AGE
reportes-service-cronjob-heartbeat-29810022   Complete   1/1           8s         4m35s
reportes-service-cronjob-heartbeat-29810024   Complete   1/1           7s         2m35s
reportes-service-cronjob-heartbeat-29810026   Complete   1/1           8s         35s
reportes-service-cronjob-resumen-29810020     Complete   1/1           10s        6m35s

[cronjob-heartbeat] insertado: carne=202300547 fecha_hora=2026-09-05 09:42:05.872833
[cronjob-heartbeat] insertado: carne=202300547 fecha_hora=2026-09-05 09:44:05.286820
[cronjob-heartbeat] insertado: carne=202300547 fecha_hora=2026-09-05 09:46:05.527726

[cronjob-resumen] publicado en 'resumenes-cronjob': {"generado_en": "2026-09-05T09:40:07...", "ejecuciones_por_hora": [{"hora": "2026-09-05T09:00:00", "ejecuciones": 3}]}
```

El `resumen` corrió solo en su ciclo real de 10 minutos (no se forzó con
`kubectl create job` como en el dry-run) — evidencia más fuerte que la
anterior para mostrar en la calificación.

### Limpieza final (2026-09-06, después de la calificación) — TODO borrado

Con la calificación ya terminada, se ejecutó la Fase 9 completa (esta vez sí
incluyendo ECR y el usuario IAM, no solo el clúster).

**Detalle real encontrado**: al reconectar en un día distinto, el contexto
activo de `kubectl` había cambiado solo a `kind-bank-usac` (otro curso, otro
clúster local) — el contexto de `sa-p6` seguía en el kubeconfig pero ya no
era el activo. Se verificó con `kubectl config get-contexts` y se cambió
explícitamente antes de borrar nada:
```bash
kubectl config use-context sa-p6-cli@sa-p6.us-east-1.eksctl.io
```
Precaución importante en cualquier limpieza de este tipo: confirmar
`kubectl get nodes` / `kubectl get namespaces` contra el clúster correcto
**antes** de un `helm uninstall`/`kubectl delete namespace`, para no
apuntar por error a un clúster de otro curso.

```bash
helm uninstall sa-p5 -n sa-p5
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace sa-p5
kubectl delete namespace ingress-nginx
eksctl delete cluster --name sa-p6 --region us-east-1
# (igual que en el dry-run: el borrado del control plane es asincrono,
# se confirmo con `aws eks describe-cluster` hasta ResourceNotFoundException)

for s in api-gateway auth-service authz-service pedidos-service productos-service reportes-service; do
  aws ecr delete-repository --repository-name "p6/${s}" --region us-east-1 --force
done

aws iam delete-access-key --user-name sa-p6-cli --access-key-id AKIAQFLZDK36SV6LHSNO
aws iam detach-user-policy --user-name sa-p6-cli --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-user --user-name sa-p6-cli
```

**Verificación final — todo vacío:**

```
$ eksctl get cluster --region us-east-1          -> No clusters found
$ aws ec2 describe-instances --region us-east-1  -> (vacio)
$ aws ec2 describe-volumes --region us-east-1    -> (vacio)
$ aws elbv2 describe-load-balancers              -> (vacio)
$ aws elb describe-load-balancers                -> (vacio)
$ aws ec2 describe-nat-gateways                  -> (vacio)
$ aws ec2 describe-addresses                     -> (vacio)
$ aws ecr describe-repositories --region us-east-1 -> (vacio)
```

Usuario IAM `sa-p6-cli` borrado al final (última acción, porque su access
key era la que se estaba usando para verificar todo lo anterior). No queda
ningún recurso de esta práctica facturando en la cuenta de AWS.

### Para el día de la calificación

Repetir, en orden: Fase 2 (crear clúster + OIDC + addon NetworkPolicy +
driver EBS + marcar `gp2` default) → Fase 4 (instalar `ingress-nginx`,
**capturar el hostname nuevo del ELB** — va a ser distinto al de hoy —
y actualizar `values-aws.yaml`) → Fase 5 (`helm install`, ya sin necesidad
de repetir Fase 1, las imágenes siguen en ECR) → Fase 6/7 (verificar y
capturar evidencia fresca, incluyendo las capturas de consola pendientes) →
al terminar la calificación, repetir esta Fase 9 completa (esta vez sí,
también borrar ECR y el usuario IAM si ya no se van a reusar).

## 12. Respuestas a las preguntas del enunciado (sección 3.2)

*(pendiente completar con evidencia real del clúster ya desplegado, pero el
razonamiento de fondo ya se puede adelantar)*

**1. ¿Qué es un clúster de Kubernetes administrado y qué diferencias tiene
frente a uno local?**
Pendiente — comparar minikube (P5: un solo contenedor `kicbase` simulando
todo un clúster en la laptop, control plane y nodo mezclados) vs. EKS
(control plane administrado por AWS, multi-AZ, fuera del control del
estudiante; nodos como EC2 reales dentro de un managed node group con su
propio Auto Scaling Group; networking real con VPC/subnets/Security Groups
en vez de un bridge de Docker; integración nativa con IAM para permisos y
con ECR para imágenes).

**2. ¿Qué es un Service de tipo LoadBalancer y cómo lo implementa el
proveedor de la nube?**
Pendiente — explicar que en minikube requiere `minikube tunnel` (simulado,
solo accesible desde la propia laptop), mientras que en EKS el
cloud-controller-manager de AWS crea de verdad un Elastic Load Balancer con
un hostname DNS público real, sin ningún paso manual adicional más que
crear el `Service`/`Ingress`.

**3. ¿Qué es un registro de contenedores y por qué es necesario para
desplegar en la nube?**
Pendiente — minikube podía cargar imágenes locales directo al daemon del
nodo (`minikube image load`); un clúster remoto no tiene acceso al docker
local del estudiante, así que necesita un registro accesible por red (ECR)
del que los nodos puedan hacer `pull` — y a diferencia de Artifact
Registry, ECR pide un repositorio por cada imagen.

**4. ¿Qué componentes del clúster administra el proveedor y cuáles siguen
siendo responsabilidad del estudiante?**
Pendiente — AWS administra: el control plane (API server, etcd multi-AZ,
parches de versión de Kubernetes), el ciclo de vida del Auto Scaling Group
del node group, el Load Balancer. Siguen siendo responsabilidad del
estudiante: el diseño de la VPC (se decidió sin NAT Gateway para ahorrar
costo), los roles IAM, los manifiestos/values del chart, las imágenes y su
contenido, los Secrets, las NetworkPolicy, dimensionar correctamente los
nodos, y el costo generado (incluyendo borrar todo al terminar, porque a
diferencia de GKE, el control plane de EKS cobra por hora sin excepción).

**5. ¿Qué costos genera el despliegue realizado y cómo podrían reducirse?**
Pendiente — completar con el dato real de la Fase 8; adelantar que ya se
redujo el costo más grande y menos obvio (el NAT Gateway, deshabilitado
desde la creación del clúster); se podría reducir más usando Spot Instances
para los nodos, un solo nodo si la ResourceQuota lo permite, y sobre todo
eliminando el clúster apenas termina la calificación (Fase 9) — a diferencia
de un clúster local, aquí el control plane de EKS cobra US$0.10/hora fijo
mientras exista, esté o no siendo usado.

## 13. Pendientes

- [x] Prerrequisitos: `aws`/`eksctl` instalados, credenciales IAM
      (`sa-p6-cli`) configuradas y verificadas (`aws sts get-caller-identity`).
- [x] Fase 1: 6 repos ECR creados y las 6 imágenes `runtime` subidas.
- [x] Fase 2: clúster `sa-p6` (2 nodos, sin NAT), OIDC, addon NetworkPolicy,
      driver EBS y StorageClass default — todo verificado.
- [x] Fase 3: `values-aws.yaml` completo con rutas de ECR y host del ELB.
- [x] Fase 4: `ingress-nginx` instalado, hostname público real obtenido.
- [x] Fase 5: plataforma instalada en EKS, 9 pods `Running`, PVCs `Bound`
      en `gp2` real.
- [x] Fase 6: CronJobs corriendo solos con el timezone correcto; cadena
      async completa (heartbeat→Postgres→resumen→RabbitMQ→consumer→Postgres)
      confirmada de punta a punta.
- [x] Fase 7: `curl` real desde internet a `/health` (200) y `/api/docs`
      (200 tras redirect) contra el ELB.
- [x] Fase 9 (dry-run): clúster, node group y ELB destruidos; verificado
      que no queda nada facturando por hora. ECR e IAM user se dejaron
      a propósito para la calificación.
- [x] Calificación completada (2026-09-05): clúster recreado, plataforma
      desplegada, CronJobs verificados corriendo solos en su ciclo natural
      con evidencia fresca (ver sección 8).
- [x] Fase 9 final (2026-09-06): clúster, node group, ELB, los 6 repos ECR
      y el usuario IAM `sa-p6-cli` — todo borrado y verificado. Nada de
      esta práctica sigue facturando.
- [ ] Pendiente (no bloqueante, solo para completar la documentación):
      capturas de consola de AWS (EKS + ECR) — se tienen en su lugar todas
      las verificaciones por CLI; y el costo real en Cost Explorer, filtrado
      por el rango 2026-09-05/06.
