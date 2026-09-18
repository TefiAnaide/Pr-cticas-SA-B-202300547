# Uso e integración del servicio de autenticación de la Práctica 2

## 1. Qué se reutiliza de la P2

El **Auth Service** y el **Authorization Service** de esta arquitectura no se diseñan desde cero:
son la evolución directa del módulo de autenticación/autorización construido en la Práctica 2
(`P2/src` y `P2/authz-service`). Se reutiliza el mismo patrón de dos procesos desacoplados:

| Práctica 2 | Práctica 3 | Se mantiene igual |
|---|---|---|
| `P2/src` (backend principal) → `services/auth.service.js`, `services/usuario.service.js`, `security/jwt.js`, `security/aes.js`, `security/cookie.js` | **Auth Service** | JWT firmado con `jsonwebtoken`, AES-256-CBC + HMAC para PII, bcrypt para contraseñas, cookie `HttpOnly` |
| `P2/authz-service` (`app.js`, `permissions.js`) | **Authorization Service** | Microservicio independiente, sin conocer el secreto del JWT, expuesto vía `POST /authorize {rol, recurso} → {allowed}` |
| `middlewares/requireRole.js` + `security/authClient.js` | Lógica de retry+backoff en el **API Gateway** (o en TXN/APR si consultan directo) | Mismo mecanismo: reintentos con backoff exponencial, `AUTHZ_MAX_RETRIES` / `AUTHZ_RETRY_BACKOFF_MS`, fail-closed si se agotan |

Esta separación en dos servicios (autenticación vs. autorización) fue un requisito explícito de la
P2 (requisito 9: "la autorización debe implementarse como un servicio independiente... desacoplado
del servicio de autenticación") y es la razón por la que en esta arquitectura **Auth Service** y
**Authorization Service** aparecen como dos cajas separadas en `01_arquitectura_general.mermaid` y
`02_diagrama_componentes.mermaid`, en lugar de fusionarse en un solo componente.

## 2. Qué cambia respecto a la P2

| Aspecto | P2 | P3 |
|---|---|---|
| Roles | `Admin`, `Cliente` | `MAKER`, `CHECKER`, `AUTHORIZER`, `ADMIN` (esquema maker-checker-authorizer) |
| Vida del token | `JWT_EXPIRES_IN` corto y configurable (ej. `15m`), pensado para una sesión web normal | **12 horas fijas**, estilo OAuth corporativo, pensado para una jornada laboral de banca corporativa |
| Renovación | Ventana de gracia `JWT_REFRESH_GRACE_SECONDS` tras expirar | Se conserva el mismo mecanismo de renovación transparente dentro de la ventana de gracia, pero aplicado sobre la ventana de 12h |
| Recursos protegidos | `ruta1` (solo Admin), `ruta2` (Admin y Cliente) | Recursos de negocio: `batch:create` (MAKER), `approval:checker` (CHECKER), `approval:authorizer` (AUTHORIZER), `core:submit` (interno) |
| Consumidores del Authorization Service | Un solo backend monolítico | Múltiples microservicios (Transaction Service, Approval Service), cada uno consultando `«IAuthorize»` con su propio retry+backoff |
| Alcance de los datos cifrados con AES | `nombre`, `correo_electronico` de `USER` | Igual: `USER.email` (y cualquier otro dato de identificación) sigue cifrado con AES-256-CBC; las contraseñas siguen con `bcrypt`, nunca con AES |

La matriz de permisos de `permissions.js` (P2) — un objeto `{ rol: [recursos] }` — se extiende
igual como datos, no como lógica ramificada (mismo principio Open/Closed documentado en el README
de la P2): agregar un recurso nuevo del core bancario es agregar una fila a `AUTHZ_ROLE_PERMISSION`
(ver `03_diagramas_ER.mermaid`), sin tocar el código del Authorization Service.

## 3. Cómo lo consumen los demás microservicios

Siguiendo el mismo contrato que en la P2 (`security/authClient.js` → `authz-service`):

1. El **API Gateway** recibe la petición del actor (Maker/Checker/Authorizer) con la cookie del JWT.
2. Llama a **Auth Service** para validar la firma/expiración del token y obtener el `rol` del payload.
3. Llama a **Authorization Service** con `{rol, recurso}` para decidir si el rol puede ejecutar la
   acción solicitada, con el mismo ciclo de reintentos con backoff exponencial de la P2 y la misma
   política **fail-closed** (si se agotan los reintentos, se deniega el acceso, nunca se asume
   permitido).
4. Solo si ambos pasos responden `OK`/`allowed:true`, el Gateway enruta la petición a **Transaction
   Service** o **Approval Service**.

Este flujo completo está documentado paso a paso en `05_secuencia_aprobacion_3_pasos.mermaid`.

## 4. Por qué se preserva el desacoplamiento

Igual que en la P2 (sección "Dependency Inversion Principle" del README de P2), el objetivo es que
la política de autorización pueda cambiar (nuevos roles, nuevos recursos, incluso un motor de
reglas distinto) sin tocar el Auth Service ni los servicios de negocio (Transaction/Approval): todos
dependen únicamente del contrato HTTP `POST /authorize`, nunca de su implementación interna. Esto
es consistente con el requerimiento técnico de la P3 de que **cada microservicio tenga su propia
base de datos independiente** — Auth Service y Authorization Service no comparten esquema ni FKs
cruzadas (ver `03_diagramas_ER.mermaid`).
