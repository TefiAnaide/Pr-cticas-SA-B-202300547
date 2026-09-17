# Informe de incidente — fallo inducido en `api-gateway`

**Fecha:** 2026-09-18 · **Servicio:** api-gateway · **Versión defectuosa:** `v0.3.1-broken` · **Versión estable:** `v0.2.0`

## Qué falló

Se publicó deliberadamente una versión de `api-gateway` con un fallo
**silencioso**: el endpoint `/health` seguía respondiendo `HTTP 200`
(pasa cualquier chequeo que solo mire el código de estado, incluidos el
`readinessProbe`/`livenessProbe` de Kubernetes), pero con el cuerpo
`{"status":"degraded"}` en vez de `{"status":"ok"}`. Un primer intento
con `HTTP 500` fue descartado como caso de prueba porque el
`readinessProbe` de Kubernetes ya lo bloqueaba por sí solo antes de
siquiera llegar al análisis del canary — no ejercitaba el mecanismo que
esta práctica pide demostrar.

## Cómo se detectó

El `AnalysisTemplate api-gateway-canary-analysis` (métrica `health-check`,
`provider: web`) consulta `/health` cada 10s, 3 veces, contra un Service
dedicado (`api-gateway-canary`) que Argo Rollouts mantiene apuntando
**solo** a los pods de la revisión en promoción — nunca a la estable.
Extrae `$.status` por `jsonPath` y lo compara con
`successCondition: result == "ok"`. A las **16:12:26 UTC** la primera
medición devolvió `"degraded"` → `Phase: Failed`.

## Cómo se contuvo

`failureLimit: 0` en la métrica: **1** medición fallida ya excede el
límite. Argo Rollouts abortó el rollout automáticamente
(`RolloutAborted: ... Metric "health-check" assessed Failed due to
failed (1) > failureLimit (0)`), sacó el ReplicaSet canary
(`Terminating`) y dejó el 100% del tráfico en la revisión estable
`v0.2.0`. El `AnalysisRun api-gateway-b8c7586d4-7-3` quedó en
`Failed` como evidencia. **0% del tráfico de usuarios reales llegó a
tocar la versión rota** — el canary nunca superó `ActualWeight: 0`.

## Tiempo de recuperación

Entre publicar la versión rota (`kubectl argo rollouts set image` a las
**10:11:39** hora local) y que el Rollout quedara `Degraded`/revertido
(**10:12:31**) pasaron **≈52 segundos**, sin intervención humana.

## Cómo prevenirlo

Agregar un smoke test de **contrato** (no solo código HTTP, sino el
cuerpo JSON completo de `/health`) como etapa de `test` en el pipeline,
**antes** de construir y publicar la imagen — así este tipo de fallo
nunca llega a generar un tag/release, en vez de depender únicamente de
que el canary lo atrape ya en el clúster.
