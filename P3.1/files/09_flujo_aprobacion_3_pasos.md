# Flujo de aprobación de 3 pasos (Maker – Checker – Authorizer)

## 1. Propósito

Ninguna transferencia, pago o depósito masivo cargado por CSV llega al **Sistema Core Bancario**
sin que tres personas distintas, con tres roles distintos, hayan aprobado el lote. Es un control de
segregación de funciones estándar en banca (nadie puede crear y aprobar su propia operación), y es
el requisito de negocio central de esta práctica.

## 2. Roles y responsabilidades

| Rol | Responsabilidad | Recurso autorizado (Authorization Service) |
|---|---|---|
| **MAKER** | Carga el archivo CSV y da la primera aprobación (creación del lote) | `batch:create` |
| **CHECKER** | Revisa el lote ya validado y lo aprueba/rechaza en segunda instancia | `approval:checker` |
| **AUTHORIZER** | Da la autorización final; su aprobación dispara el envío al core bancario | `approval:authorizer` |
| **ADMIN** | Rol administrativo, no participa en el flujo de aprobación de un lote propio | — |

Regla de negocio explícita: **un mismo usuario no puede ejecutar dos pasos del mismo lote**
(el Maker de un lote no puede además ser su Checker o Authorizer). Esta validación la hace
**Approval Service** comparando el `userId` de cada `APPROVAL_STEP` dentro de un mismo
`APPROVAL_FLOW` antes de aceptar una nueva decisión.

## 3. Estados del lote (`BATCH.status`) y del flujo (`APPROVAL_FLOW`)

```
PENDING_CHECKER → PENDING_AUTHORIZER → APPROVED → SUBMITTED_TO_CORE
       │                  │
       └────── REJECTED ◄─┘   (en cualquier paso, con `comment` obligatorio)
```

- **PENDING_CHECKER**: el Maker cargó el CSV, Transaction Service validó las reglas de negocio
  (saldo disponible, límites de transacción, cuentas válidas, prevención de fraude — ver
  `10_estrategia_almacenamiento_csv.md`) y Approval Service registró el primer `APPROVAL_STEP`
  (`stepType=MAKER`, `decision=APPROVED`).
- **PENDING_AUTHORIZER**: el Checker aprobó. Si el Checker rechaza, el flujo pasa directo a
  `REJECTED` y el lote completo queda `REJECTED` (no se notifica a nadie).
- **APPROVED**: el Authorizer dio la tercera y última aprobación. Approval Service publica el
  evento `BatchFullyApproved(batchId)` en el Event Bus.
- **SUBMITTED_TO_CORE**: Transaction Service consumió el evento, envió las transacciones al core
  bancario y guardó el `CORE_SUBMISSION` correspondiente (ver `06_secuencia_core_bancario.mermaid`).

Un rechazo en cualquiera de los 3 pasos es **terminal**: no hay reintento automático del mismo
lote, el Maker debe corregir y volver a cargar un CSV nuevo (un nuevo `BATCH`).

## 4. Validación de identidad y permiso en cada paso

Cada uno de los 3 pasos repite el mismo patrón (documentado en detalle en
`05_secuencia_aprobacion_3_pasos.mermaid` y en `08_integracion_p2.md`):

1. El actor llama al **API Gateway** con su cookie de sesión (JWT de 12h).
2. El Gateway valida el token contra **Auth Service**.
3. El Gateway valida el permiso del rol contra **Authorization Service**
   (`{rol, recurso}` → `{allowed}`, con retry+backoff).
4. Solo si ambas validaciones pasan, **Approval Service** registra el `APPROVAL_STEP` con
   `decidedAt`, `decision` y `comment` (obligatorio solo si `decision=REJECTED`).

## 5. Al completar el paso 3

Cuando `AUTHORIZER` aprueba:

1. `ApprovalFlow.status = APPROVED`.
2. Approval Service publica `StepApproved` (cada paso) y, al cerrar el tercero, también
   `BatchFullyApproved(batchId)` en el Event Bus.
3. **Transaction Service** consume `BatchFullyApproved`, envía el lote al core bancario
   (`06_secuencia_core_bancario.mermaid`) y publica `TransactionsSubmitted(batchId)`.
4. **Notification Service** consume el evento y envía el correo "su transacción está en proceso" a
   cada beneficiario del lote (`07_secuencia_notificacion_clientes.mermaid`).
5. **Logging Service** registra cada transición de estado del flujo, con `traceId` compartido entre
   los tres pasos para poder auditar el lote completo de punta a punta.
