# Guía de demostración — Práctica 7 (CI/CD)

Script para la sesión de calificación (12/09/2026). Está armado directo
sobre la rúbrica real de la práctica (sección 8, "Detalle de la
Calificación" — la 8.2 del PDF solo trae los puntajes, no los criterios;
los criterios con los que de verdad califican están en la tabla de la
página 9-10). Cada bloque dice **qué mostrar**, **cómo mostrarlo** y **qué
puntos cubre**.

No leas esto en voz alta frente al catedrático — son notas para vos. La
rúbrica penaliza explícitamente "respuestas copiadas o sin análisis"
(1.4); la idea es que entiendas el porqué de cada decisión (está en
[`Practica7.md`](Practica7.md), sección 1) y lo expliques con tus propias
palabras.

## 0. Checklist previo (antes de la sesión)

- [ ] Práctica 5 y 6 calificadas (requisito de la 8.1 — sin esto no
      califica esta práctica).
- [ ] Correr el pipeline al menos una vez de punta a punta **antes** de la
      sesión (push a `main` o `workflow_dispatch`) y confirmar que las 4
      etapas terminan en verde. Si algo falla, arreglarlo con margen —
      no depures en vivo frente al catedrático.
- [ ] Tener a la mano, ya abiertas en el navegador:
  - pestaña **Actions** del repo, con una corrida completa en verde
  - pestaña **Packages** del repo (o `https://github.com/<owner>?tab=packages`)
    mostrando las 6 imágenes en GHCR
  - el archivo [`.github/workflows/ci-cd.yml`](../../.github/workflows/ci-cd.yml)
  - [`Practica7.md`](Practica7.md) y este archivo
- [ ] Guardar capturas de una corrida exitosa (Actions + Packages +
      `kubectl get pods`) como respaldo, **por si la demo en vivo falla**
      por algo de red o de cuota del runner — mejor mostrar evidencia
      grabada que quedarte sin nada que enseñar.
- [ ] Confirmar que el repo tiene **Settings → Actions → General →
      Workflow permissions → Read and write permissions** activado (si no,
      el job `build-and-push` falla con 403 al hacer push a GHCR).

## 1. Organización del repositorio — criterio 1.3 (5 pts)

**Mostrar:** el árbol del repo, enfocando:

```
P7/
├── doc/
│   ├── Practica7.md
│   └── GuiaDemostracion.md
.github/
└── workflows/
    └── ci-cd.yml
```

**Decir:** el workflow vive en `.github/workflows/` porque ahí es donde
GitHub Actions los descubre (no dentro de `/P7` — expliqué esto también en
`Practica7.md` sección 0). La documentación y el diagrama sí viven en
`/P7/doc/`, que es lo que pide el entregable.

## 2. Documentación técnica — criterio 1.1 (10 pts)

**Mostrar:** `Practica7.md`, recorriendo en este orden (no leer el archivo
completo, señalar las secciones):

1. Sección 1 (tabla de decisiones) — **esta es la parte que más impresiona
   en una demo**: no solo dice qué se usó, dice qué se descartó y por qué.
   Ejemplo a explicar de memoria: *"los tests no levantan Postgres real
   porque `productos-service` abre el pool de conexión al importar el
   módulo, con reintentos de hasta 20 segundos — meter eso en el paso de
   test lo hace lento y frágil por una razón que no tiene que ver con lo
   que se está probando"*.
2. Sección 3 (las 4 etapas) — relacionar cada una con un job real que se
   ve en la pestaña Actions.
3. Sección 5 (secretos) — por qué los secretos del deploy de CI son
   efímeros y no van en GitHub Secrets.

## 3. Diagrama del pipeline — criterio 1.2 (10 pts)

**Mostrar:** el diagrama Mermaid de `Practica7.md` sección 2 (se renderiza
solo en GitHub/VS Code). Señalar las 4 fases y explicar **las flechas**, no
solo las cajas:

- por qué `test-node` y `test-python` corren en paralelo (no dependen
  entre sí)
- por qué hay una bifurcación en "¿Es pull_request?" (en un PR el pipeline
  se detiene después de test, no hace push ni deploy)
- por qué `deploy-k8s` hace `docker pull` + `kind load docker-image` en
  vez de que el clúster jale la imagen directo de GHCR (evita configurar
  credenciales dentro del clúster efímero)

## 4. Pipeline CI/CD — criterio 2.1 (20 pts)

Este es el criterio con más peso. La rúbrica pide específicamente que
funcione **"ante nuevos commits/PR"** — no basta con mostrar una corrida
vieja, hay que **disparar una corrida en vivo**.

**Hacerlo en vivo:**

```bash
cd P5/authz-service
# un cambio trivial y visible, p.ej. un comentario o un test mas
git add -A
git commit -m "demo: disparar pipeline en vivo"
git push
```

Abrir la pestaña Actions y mostrar cómo aparece la corrida nueva, con
`test-node` y `test-python` corriendo en paralelo. Mientras corre (toma
1-2 min), explicar el `strategy.matrix` — que si un servicio falla su
test, los otros 5 jobs de la matriz no se bloquean.

**Alternativa más rápida si hay poco tiempo:** abrir un Pull Request desde
una rama, y mostrar que el pipeline corre solo hasta test/build (el job
`deploy-k8s` no aparece porque `if: github.event_name != 'pull_request'`)
— esto además demuestra que entendés el control de flujo del workflow, no
solo que "funciona".

## 5. Automatización Docker — criterio 2.2 (15 pts)

**Mostrar:**

1. El job `build-and-push` en la corrida verde, expandiendo el paso
   "Build y push de la imagen" de cualquiera de los 6 — se ve el
   `docker buildx build --target runtime` y el push a
   `ghcr.io/.../p5-<servicio>`.
2. La pestaña **Packages** del repo (o del perfil/org) con las 6 imágenes,
   cada una con al menos dos tags: el SHA del commit que se acaba de
   empujar y `latest`.

**Decir:** el tag con el SHA es el que realmente se usa para desplegar
(trazabilidad exacta commit → imagen → deploy); `latest` es solo
conveniencia para quien quiera revisar la imagen manualmente.

## 6. Deploy automático — criterio 2.3 (15 pts)

**Mostrar:** el job `deploy-k8s` expandido, en orden:

1. Paso "Crear cluster de Kubernetes local (kind)" — un clúster real
   creado desde cero en el runner, no una simulación.
2. Paso "Descargar imágenes y cargarlas en el cluster kind" — las 6
   imágenes recién publicadas entrando al clúster.
3. Paso "Deploy con Helm" — el `helm upgrade --install` completo.
4. Paso "Verificar pods y servicios desplegados" — la salida de
   `kubectl get pods -n sa-p5` con los pods en `Running`/`Ready`.
5. Paso "Smoke test del api-gateway" — el `curl /health` respondiendo
   `200` contra el sistema ya desplegado, con Postgres y RabbitMQ reales
   corriendo dentro del mismo clúster.

**Decir:** esto no es un despliegue simulado — es el mismo chart de Helm
de la Práctica 5, con Postgres y RabbitMQ reales (Bitnami), reconstruido
desde cero en cada corrida y destruido al terminar el job. Nadie lo tocó a
mano.

## 7. Versionamiento — criterio 2.4 (10 pts)

**Mostrar:** el bloque `on:` de `ci-cd.yml` (sección 4 de `Practica7.md`
lo explica). Señalar los 4 disparadores y qué hace cada uno.

**Opcional, si sobra tiempo — demostrarlo con un tag real:**

```bash
git tag v1.0.0
git push origin v1.0.0
```

y mostrar cómo el push del tag dispara el pipeline completo igual que un
push a `main` — evidencia de que el versionamiento por tags realmente
funciona, no solo que está escrito en el YAML.

## 8. Preguntas teóricas — criterio 1.4 (15 pts)

No hay preguntas teóricas escritas en el enunciado de esta práctica — se
espera que te las hagan de forma oral durante la demo. Preparate para
explicar, **con tus palabras**, apoyándote en lo que realmente construiste
(no en definiciones genéricas de libro):

- **¿Cuál es la diferencia entre CI y CD en tu pipeline?** CI es
  `test-node`/`test-python`/`build-and-push` (valida e integra cada
  cambio); CD es `deploy-k8s` (lo lleva a un entorno corriendo sin
  intervención manual).
- **¿Por qué el deploy no corre en un Pull Request?** Para que un PR sea
  solo un *gate* de calidad (test + build), sin gastar recursos
  desplegando algo que todavía no se aprobó, y sin necesitar credenciales
  de push en PRs de forks.
- **¿Qué pasa si `helm upgrade --install` corre dos veces con el mismo
  release?** Es idempotente — actualiza el release existente en vez de
  fallar o duplicar recursos; por eso funciona igual en la primera corrida
  del día que en la corrida 50.
- **¿Por qué kind y no un clúster persistente?** El pipeline necesita
  reproducibilidad: cada corrida debe partir de un estado limpio conocido,
  no arrastrar configuración manual de corridas anteriores. Un clúster
  persistente además tendría un costo/mantenimiento que no aporta nada a
  lo que se está demostrando (la automatización, no la infraestructura).
- **¿Por qué los tests no usan una base de datos real?** Ver la tabla de
  decisiones de `Practica7.md` — el pool de conexión se abre al importar
  el módulo, con reintentos de hasta 20s; probarlo ahí habría hecho el
  paso de test lento y frágil por una causa ajena a la lógica que se
  prueba. La integración real con la base de datos se valida en el deploy.
- **¿Qué garantiza que la imagen que se despliega es la que se acaba de
  construir, y no una vieja?** El tag de la imagen es el SHA exacto del
  commit (`${{ github.sha }}`), no `latest` — el deploy usa ese mismo SHA
  vía `--set <servicio>.image.tag`, así que no hay ambigüedad de qué
  versión corre.

## 9. Si algo falla en vivo

- **`build-and-push` falla con 403** → revisar Settings → Actions →
  Workflow permissions (ver checklist 0).
- **`deploy-k8s` se queda colgado en `helm upgrade --install ... --wait`**
  → probable timeout de Postgres/RabbitMQ arrancando; mostrar la captura
  de respaldo de una corrida anterior exitosa y explicar que ya se validó
  antes (mejor esto que perder tiempo de la sesión depurando).
- **El runner tarda mucho en el smoke test** → normal, Postgres + RabbitMQ
  + 6 microservicios tardan 2-4 min en estar `Ready`; llenar ese tiempo
  explicando la sección 1 de `Practica7.md` mientras corre.
