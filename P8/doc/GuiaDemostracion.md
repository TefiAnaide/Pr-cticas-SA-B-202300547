# Guía de demostración — Práctica 8 (GitOps, entrega progresiva y seguridad)

Script para la sesión de calificación. Basado en el script de verificación
real que se usará (`P8/Fix_Script_p8.sh`) — cada bloque dice qué verifica
ese script exactamente, para que no haya sorpresas.

## 0. Checklist previo

- [ ] `p8.conf` generado (`./Fix_Script_p8.sh --init`) y lleno con los
      datos reales: `CARNET`, `REPO_CODE`, `REPO_GITOPS`, `APP=sa-p8`,
      `NS=sa-p8`, `IMAGE` (una imagen firmada real, ej.
      `ghcr.io/tefianaide/pr-cticas-sa-b-202300547/p8-api-gateway:v0.2.0`),
      `COSIGN_IDENTITY_REGEXP=https://github.com/TefiAnaide/Pr-cticas-SA-B-202300547/.*`,
      `COSIGN_ISSUER=https://token.actions.githubusercontent.com`.
- [ ] Ambos repos (código y GitOps) pusheados y **públicos**.
- [ ] Clúster `kind` corriendo, con `kubectl config current-context`
      apuntando a él, ArgoCD/Argo Rollouts/Kyverno/Sealed-Secrets
      instalados, Terraform aplicado, y la `Application` de ArgoCD en
      `Synced`/`Healthy`.
- [ ] `kubectl argo rollouts get rollout api-gateway -n sa-p8` en
      `Healthy` antes de que llegue el catedrático.
- [ ] Correr `./Fix_Script_p8.sh` una vez antes de la sesión y revisar
      `reporte_p8_<carnet>.txt` — arreglar lo que salga en rojo con
      margen, no en vivo.

## 1. Eliminatorios (sección 8.1) — si algo de esto falla, no hay nota

El script revisa, en orden: que ambos repos sean clonables sin login,
que exista `/P8` y `/P8/README.md`, que **ningún** workflow de
`.github/workflows/` (de cualquier práctica) tenga `kubectl apply/set
image/patch/create/delete`, `helm upgrade/install` ni la palabra
`kubeconfig` — y que la `Application` de ArgoCD exista, esté `Synced` y
`Healthy`, y que exista al menos un `Rollout` en el namespace.

**Mostrar:** `kubectl get application sa-p8 -n argocd` y
`kubectl argo rollouts get rollout api-gateway -n sa-p8` en vivo, antes
de entrar al detalle.

## 2. Terraform — criterio 2.1 (8 pts)

**Mostrar:** `P8/terraform/*.tf`, y correr en vivo:

```bash
cd P8/terraform
terraform init -backend=false && terraform validate
```

Señalar `namespace.tf` (namespace + quota + limits, mismos valores que
tenía el chart de Helm en P5) y `rbac.tf` (`for_each` sobre los 6
servicios — mínimo privilegio, cada uno solo lee su propio ConfigMap).

## 3. Helm — criterio 2.2 (8 pts)

**Mostrar:** el chart en el repo GitOps (`chart/`, 6 subcharts + 2
dependencias Bitnami), y `helm lint --with-subcharts` corriendo en el
job `helm-lint` de `ci-cd-p8.yml`. Señalar `values-images.yaml` — el
único archivo que el pipeline toca automáticamente.

## 4. GitOps con ArgoCD — criterio 2.3 (14 pts, el más pesado)

**Mostrar:**

1. `kubectl get application sa-p8 -n argocd -o yaml` (o `argocd app get
   sa-p8`) — `sync: Synced`, `health: Healthy`, `repoURL` apuntando al
   repo GitOps real.
2. `.github/workflows/ci-cd-p8.yml`, job `open-gitops-pr` — el
   `peter-evans/create-pull-request` que abre el PR, **nunca** un push
   directo a `main` del repo GitOps.
3. **En vivo, si hay tiempo:** hacer un tag nuevo (`git tag v0.2.1 && git
   push origin v0.2.1`) y mostrar cómo aparece el PR automático en
   `Practicas-SA-GitOps` — mergearlo y ver a ArgoCD sincronizar solo.

## 5. Entrega progresiva y reversión — criterio 2.4 (14 pts)

Este es el que más conviene demostrar **en vivo**, no solo mostrar
capturas — ya lo probamos una vez de punta a punta y funciona:

```bash
# version buena (sube 20 -> 35 -> 50, pasa el analisis y promueve solo a 100%)
kubectl argo rollouts set image api-gateway -n sa-p8 \
  api-gateway=ghcr.io/tefianaide/pr-cticas-sa-b-202300547/p8-api-gateway:v0.2.1
kubectl argo rollouts get rollout api-gateway -n sa-p8 --watch
```

Para la version mala, tener ya construida y cargada una imagen con
`/health` devolviendo `{"status":"degraded"}` con HTTP 200 (fallo
silencioso — un 500 lo bloquea antes el `readinessProbe`, no llega a
ejercitar el análisis):

```bash
kubectl argo rollouts set image api-gateway -n sa-p8 \
  api-gateway=ghcr.io/tefianaide/pr-cticas-sa-b-202300547/p8-api-gateway:v0.3.1-broken
kubectl argo rollouts get rollout api-gateway -n sa-p8 --watch
# ~50s despues: Status Degraded, RolloutAborted, AnalysisRun Failed
```

**Decir:** el `AnalysisTemplate` pega contra un Service `-canary`
dedicado (no el compartido) — expliquen por qué, es el hallazgo más
interesante de esta práctica (ver `Practica8.md` sección 6).

## 6. Validación automatizada — criterio 2.5 (8 pts)

**Mostrar:** `P8/k6/load-test.js` (thresholds `p(95)<500ms`,
`http_req_failed<1%`) y el reporte ya corrido en
`P8/k6/reportes/reporte-load-test.txt`. Señalar que el
`AnalysisTemplate` usa `provider: web` (no `job`) — mencionar que se
evaluó `job` (correr k6 como Job de Kubernetes dentro del análisis) pero
se eligió `web` por ser más rápido de verificar bajo el tiempo
disponible, sin perder el punto del criterio (`provider.web` cuenta
igual que `provider.job`).

## 7. Cadena de suministro y políticas — criterio 2.6 (8 pts)

**Mostrar:**

1. El job `build-scan-sign-push` de `ci-cd-p8.yml`: Trivy (bloquea con
   `exit-code: 1` + `severity: CRITICAL`) → SBOM → push → Cosign sign +
   verify.
2. `cosign verify` en vivo contra una imagen real publicada:
   ```bash
   cosign verify ghcr.io/tefianaide/pr-cticas-sa-b-202300547/p8-api-gateway:v0.2.0 \
     --certificate-identity-regexp "https://github.com/TefiAnaide/Pr-cticas-SA-B-202300547/.*" \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```
3. `kubectl get clusterpolicy` (3 políticas, `Enforce`) y el rechazo en
   vivo:
   ```bash
   kubectl run test-latest --image=nginx:latest -n sa-p8
   # admission webhook "validate.kyverno.svc-fail" denied — 2 politicas a la vez
   ```
4. `kubectl get sealedsecrets -n sa-p8` y explicar por qué el repo
   GitOps no tiene ningún secreto en texto plano.

## 8. Preguntas teóricas — criterio 1.4 (14 pts)

Preparar respuestas propias (no genéricas) para:

- **¿Por qué el pipeline no puede hacer `helm upgrade` directo?** Rompe
  la garantía central de GitOps: que el repo sea la única fuente de
  verdad. Si el pipeline también aplica cambios, hay dos caminos para
  modificar el clúster y pueden divergir sin que nadie lo note.
- **¿Qué pasa si alguien hace `kubectl edit` a mano sobre un recurso que
  ArgoCD administra?** `selfHeal: true` en el `syncPolicy` lo revierte
  automáticamente al estado declarado en Git en el siguiente ciclo de
  reconciliación.
- **¿Por qué el `AnalysisTemplate` no puede pegarle al Service
  compartido?** Ver el hallazgo de la sección 6 de `Practica8.md` —
  contestar con el ejemplo real (mediciones `"ok"`/`"degraded"`
  alternadas), no en abstracto.
- **¿Qué garantiza que la imagen que ArgoCD despliega es exactamente la
  que pasó Trivy y quedó firmada?** El PR automático solo cambia el
  `tag:` en `values-images.yaml` al mismo valor que se acaba de
  construir, escanear, firmar y publicar — no hay ningún paso manual
  entre "firmar" y "declarar en Git" donde el tag pueda cambiar.
- **¿Por qué Sealed Secrets y no simplemente no versionar los secretos?**
  Porque GitOps exige que el estado deseado esté *completo* en Git — un
  secreto ausente del repo es un secreto que ArgoCD no puede reconciliar
  ni detectar si alguien lo borra a mano del clúster.

## 9. Si algo falla en vivo

- **ArgoCD no sincroniza / queda `OutOfSync`:** revisar que el push al
  repo GitOps ya llegó a `main` y que el PR del pipeline (si aplica) ya
  se mergeó — ArgoCD solo ve lo que está en `main`.
- **El Rollout no avanza:** `kubectl describe rollout api-gateway -n
  sa-p8` — casi siempre es la imagen (no cargada en el clúster) o el
  `AnalysisTemplate` (Service `-canary` sin endpoints todavía, esperar
  unos segundos más).
- **Kyverno no rechaza nada:** confirmar `validationFailureAction:
  Enforce` (no `Audit`) con `kubectl get clusterpolicy -o yaml`.
