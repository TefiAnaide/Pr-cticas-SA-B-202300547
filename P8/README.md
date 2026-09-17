# Práctica 8 — GitOps, entrega progresiva y seguridad de la cadena de suministro

Documentación técnica completa: [`doc/Practica8.md`](doc/Practica8.md) ·
Diagrama del flujo: dentro del mismo archivo (sección 2, Mermaid) ·
Informe del fallo inducido: [`doc/InformeIncidente.md`](doc/InformeIncidente.md) ·
Guía de demostración: [`doc/GuiaDemostracion.md`](doc/GuiaDemostracion.md)

Repositorio GitOps (manifiestos, aparte de este repo de código):
**https://github.com/TefiAnaide/Practicas-SA-GitOps**

## 4.1 Tabla de enlaces obligatoria

> **PENDIENTE DE LLENAR** — las filas marcadas `<<COMPLETAR>>` requieren
> que el pipeline real corra en GitHub (no se puede generar la URL de una
> corrida de Actions sin que exista) y que el PR automático al repo
> GitOps se abra y (opcionalmente) se mergee. Ver el checklist al final
> de este README para el orden exacto de pasos.

| Ítem | Enlace o dato requerido |
|---|---|
| Repositorio GitOps | https://github.com/TefiAnaide/Practicas-SA-GitOps |
| Aplicación en ArgoCD | `sa-p8`, namespace `sa-p8` |
| Ejecución exitosa del pipeline | `<<COMPLETAR: URL del run de ci-cd-p8.yml en Actions>>` |
| Reversión automática | `<<COMPLETAR: URL del run + evidencia del Rollout>>` — ver [`InformeIncidente.md`](doc/InformeIncidente.md), reproducido localmente: `AnalysisRun api-gateway-b8c7586d4-7-3` en `Failed`, Rollout `RolloutAborted` a las 16:12:26 UTC |
| Despliegue rechazado por política | `kubectl run test-latest --image=nginx:latest -n sa-p8` → bloqueado por `disallow-latest-tag` y `require-non-root` simultáneamente (ver `doc/Practica8.md` sección 8) |
| Bloqueo por vulnerabilidad crítica | `<<COMPLETAR: URL del Pull Request bloqueado por Trivy, si se induce una CVE de prueba>>` |
| Imagen firmada | `ghcr.io/tefianaide/pr-cticas-sa-b-202300547/p8-api-gateway:v0.2.0` (verificada localmente con `cosign verify` durante el pipeline) |
| Reporte de prueba de carga | [`P8/k6/reportes/reporte-load-test.txt`](k6/reportes/reporte-load-test.txt) |
| Video demostrativo | `<<COMPLETAR: URL + minutaje por punto demostrado>>` |

## Checklist para completar la entrega

1. **Crear el secreto `GITOPS_PAT`** en este repo (Settings → Secrets and
   variables → Actions) — un Personal Access Token (fine-grained, con
   permiso `contents: write` y `pull requests: write` sobre
   `Practicas-SA-GitOps`). Sin esto, el job `open-gitops-pr` del
   pipeline falla.
2. Verificar que **Settings → Actions → Workflow permissions** esté en
   "Read and write" (igual que en P7).
3. Hacer commit y push de este repo (`P8/`, `.github/workflows/ci-cd.yml`
   modificado, `.github/workflows/ci-cd-p8.yml` nuevo) y del repo GitOps
   (`chart/`, `policies/`, `argocd-application.yaml`).
4. Crear un tag y pushearlo para disparar el pipeline real:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
5. Cuando el pipeline termine, copiar la URL del run de Actions a la
   tabla de arriba.
6. Revisar/mergear el Pull Request que el pipeline abre en
   `Practicas-SA-GitOps` — eso dispara la sincronización real de ArgoCD.
7. Aplicar `argocd-application.yaml` al clúster real donde se hará la
   demostración (`kubectl apply -f argocd-application.yaml -n argocd`)
   si aún no está aplicado ahí.
8. Grabar el video demostrativo siguiendo
   [`doc/GuiaDemostracion.md`](doc/GuiaDemostracion.md) y completar la
   última fila de la tabla.
