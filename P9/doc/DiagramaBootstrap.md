# Diagrama del bootstrap — Práctica 9

Orden de reconstrucción y dependencias entre componentes cuando se corre
`./P9/bootstrap.sh` después de perder el clúster. Cada caja depende de
las que tiene encima: no puede empezar hasta que esas terminen sanas.

**Leyenda:**
- 🟦 **Automático:** lo hace el bootstrap sin intervención.
- 🟨 **Sobrevive al desastre:** existe antes y fuera del clúster; el bootstrap lo lee, no lo crea.
- 🟥 **Manual:** lo hace una persona.

En la reconstrucción solo hay **un** paso manual: lanzar el comando.

```mermaid
flowchart TD
    H(["🟥 Operador: ./P9/bootstrap.sh"])

    subgraph SOBREVIVE["🟨 Fuera del clúster (sobrevive al desastre)"]
        GH[("GitHub<br/>repo código + repo GitOps")]
        ENV[/"~/.sa-p9/minio.env<br/>credenciales MinIO"/]
        VOL[("Volumen Docker de MinIO<br/>sa-p9-tfstate · sa-p9-velero · sa-p9-llaves")]
    end

    subgraph F1["Fase 1 · Almacenamiento externo"]
        MINIO["🟦 docker compose up<br/>contenedor sa-p9-minio<br/>(crea buckets solo si faltan)"]
    end

    subgraph F2["Fase 2 · Llave"]
        KEY["🟦 Descarga la llave de Sealed Secrets<br/>s3://sa-p9-llaves → ~/.sa-p9/sealed-secrets/"]
    end

    subgraph F3["Fase 3 · Terraform (estado remoto en MinIO, use_lockfile)"]
        TFI["🟦 terraform init<br/>backend s3 → MinIO"]
        KIND["🟦 kind_cluster sa-p9<br/>1 control-plane + 2 workers"]
        SC["🟦 StorageClass<br/>local-respaldable"]
        NS["🟦 Namespace sa-p8<br/>cuota · LimitRange · RBAC"]
        SSK["🟦 Secret de la llave<br/>kube-system (label active)"]
        ARGO["🟦 helm_release ArgoCD"]
        ROOT["🟦 Application raíz<br/>sa-p9-root → apps/"]
    end

    subgraph F4["Fase 4 · ArgoCD app-of-apps (por sync-waves)"]
        W3["🟦 ola -3 · sealed-secrets<br/>usa la llave inyectada"]
        W2["🟦 ola -2 · argo-rollouts · kyverno"]
        W1["🟦 ola -1 · velero-credenciales<br/>(SealedSecret)"]
        W0["🟦 ola 0 · velero + 2 Schedules<br/>· politicas-kyverno"]
        WP["🟦 ola 1 · sa-p8<br/>microservicios · Postgres · RabbitMQ"]
    end

    subgraph F5["Fases 5-7 · Datos y verificación"]
        RK["🟦 Re-respalda la llave → MinIO"]
        SYNC["🟦 Velero sincroniza los respaldos<br/>existentes desde el bucket"]
        RES["🟦 restaurar-datos.sh<br/>último backup sa-p8 anterior al bootstrap<br/>(pausa ArgoCD → restore → reanuda)"]
        VER["🟦 Verificación: apps Synced/Healthy ·<br/>SealedSecrets descifrados · /health · filas"]
        RTO(["🟦 Imprime RTO medido"])
    end

    H --> MINIO
    ENV --> MINIO
    VOL --> MINIO
    MINIO --> KEY
    MINIO --> TFI
    KEY --> SSK
    TFI --> KIND
    KIND --> SC & NS & SSK & ARGO
    ARGO --> ROOT
    SC --> ROOT
    NS --> ROOT
    SSK --> ROOT
    GH --> ROOT
    ROOT --> W3 --> W2 --> W1 --> W0 --> WP
    WP --> RK
    W0 --> SYNC
    VOL -.respaldos.-> SYNC
    RK --> RES
    SYNC --> RES
    RES --> VER --> RTO
```

## Por qué este orden

| Dependencia | Qué pasa si se invierte |
|---|---|
| MinIO **antes** de Terraform | `terraform init` no encuentra el backend y no sabe qué existía: sin estado no hay reconstrucción reproducible. |
| Llave **antes** del controlador de Sealed Secrets | El controlador genera una llave nueva y los SealedSecrets del repo GitOps quedan ilegibles para siempre en ese clúster. Por eso Terraform crea el Secret de la llave antes de `sa-p9-root` (`depends_on` en `argocd.tf`). |
| Namespace, RBAC y StorageClass **antes** de la app raíz | Los charts usan `serviceAccount.create=false`, `CreateNamespace=false` y la StorageClass `local-respaldable`: sin ellos los pods no arrancan o el volumen de Postgres no se puede respaldar. |
| Ola -3 → -2 → -1 → 0 → 1 | Cada ola usa los CRDs o secretos de la anterior: `velero-credenciales` es un SealedSecret (necesita la ola -3); `sa-p8` usa `Rollout` (ola -2) y sus pods pasan por las políticas de Kyverno (olas -2 y 0). Una ola no empieza hasta que la anterior está `Healthy` (health check de `Application` en `P9/terraform/values/argocd.yaml`). |
| Restauración **después** de que `sa-p8` esté sano | Velero restaura el StatefulSet de Postgres con su volumen; si ArgoCD siguiera con `selfHeal`, recrearía Postgres con un disco vacío antes de la restauración. Por eso `restaurar-datos.sh` pausa `sa-p9-root` y `sa-p8` y los reactiva al terminar. |
| Solo backups **anteriores** al bootstrap | El Schedule horario usa `skipImmediately: true` para no guardar la base vacía del clúster nuevo como "el respaldo más reciente", y el bootstrap ignora cualquier respaldo creado después de su inicio. |

## Lo que no es automático

| Paso | Por qué sigue siendo manual | Dónde está documentado |
|---|---|---|
| Lanzar `./P9/bootstrap.sh` | Decidir que hay un desastre es una decisión humana. | [Runbook §1](Runbook_Recuperacion.md#1-pérdida-total-del-clúster) |
| Recrear `~/.sa-p9/minio.env` si se pierde la máquina | Son credenciales: no deben estar en ningún repositorio. | Informe de DR, puntos únicos de fallo |
| Regenerar secretos si se pierden **las dos** copias de la llave | Requiere conocer los valores en claro. | [Runbook §4.3](Runbook_Recuperacion.md#43-si-no-existe-ninguna-copia-de-la-llave) |
