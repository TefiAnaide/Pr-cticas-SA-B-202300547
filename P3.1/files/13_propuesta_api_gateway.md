# Propuesta de API Gateway

## 1. Rol dentro de la arquitectura

El API Gateway es el **único punto de entrada** para el cliente (App Web/Móvil de Banca
Corporativa). Ningún microservicio se expone directamente a internet; todo pasa por el Gateway,
como se ve en `01_arquitectura_general.mermaid` y `02_diagrama_componentes.mermaid`.

## 2. Responsabilidades

1. **Enrutamiento**: dirige cada petición al microservicio correspondiente (Auth, Authorization,
   Transaction, Approval, Logging) según el path (`/auth/*`, `/batches/*`, `/approvals/*`, etc.).
2. **Autenticación de borde**: antes de enrutar, valida el JWT contra Auth Service. Si no hay
   sesión válida, corta la petición ahí mismo con `401`, sin gastar recursos de los servicios de
   negocio.
3. **Autorización de borde**: para rutas protegidas por rol, consulta Authorization Service
   (`{rol, recurso}`) con el mismo mecanismo de retry+backoff de la P2 antes de enrutar. Si el
   servicio de autorización no responde tras agotar los reintentos, deniega por defecto
   (fail-closed) en vez de dejar pasar la petición.
4. **Agregación mínima**: para el historial consultable de lotes, puede combinar la respuesta de
   Transaction Service (datos del lote) con la URL firmada de descarga del CSV (Cloud Storage), sin
   que el cliente tenga que llamar a dos servicios por separado.
5. **Cross-cutting concerns**: rate limiting por usuario/rol, CORS, logging de acceso (qué se pidió,
   quién, cuándo — reenviado a Logging Service), propagación del `traceId` a todos los servicios
   internos.
6. **Aislamiento de la topología interna**: el cliente nunca conoce las URLs internas de Transaction
   Service, Approval Service, etc. — eso permite escalar, mover o reemplazar un microservicio sin
   romper al cliente.

## 3. Qué el Gateway explícitamente NO hace

- No contiene reglas de negocio (validación de CSV, flujo de aprobación) — eso vive en Transaction
  Service y Approval Service.
- No decide permisos por sí mismo — siempre delega en Authorization Service, igual que en la P2
  (ningún componente reimplementa la matriz de permisos localmente).
- No mantiene estado transaccional propio: es un componente sin base de datos propia (no aparece
  ninguna `DB Gateway` en el diagrama de arquitectura), stateless, para poder escalar
  horizontalmente sin coordinación entre instancias.

## 4. Patrón y justificación técnica

Se sigue el patrón estándar **API Gateway** (Microsoft Azure Architecture Center / patrón descrito
en *Building Microservices*, Sam Newman): centraliza los *cross-cutting concerns* que, de otro modo,
cada microservicio tendría que reimplementar por separado (validar JWT, consultar autorización, rate
limiting). Esto es especialmente relevante aquí porque **tanto Transaction Service como Approval
Service necesitan las mismas dos validaciones** (token + permiso) antes de aceptar cualquier
petición — resolverlo una sola vez en el Gateway evita duplicar esa lógica en cada microservicio de
negocio.

## 5. Ejemplo de enrutamiento

| Método + Path público | Servicio destino | Validaciones en el Gateway |
|---|---|---|
| `POST /api/batches` | Transaction Service | JWT válido + `{rol, batch:create}` |
| `PUT /api/approvals/{id}/step` | Approval Service | JWT válido + `{rol, approval:checker\|approval:authorizer}` según el paso |
| `GET /api/batches/{id}/history` | Transaction Service | JWT válido (cualquier rol autenticado con acceso al lote) |
| `POST /api/auth/login` | Auth Service | Ninguna (endpoint público) |
| `GET /api/logs` | Logging Service | JWT válido + rol `ADMIN`/auditoría |
