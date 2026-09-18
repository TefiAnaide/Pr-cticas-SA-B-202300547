# Comunicación entre servicios (REST y mensajería)

## 1. Criterio de decisión

Se usan **ambos** estilos, no por preferencia sino porque cada flujo tiene una necesidad distinta:

- **REST síncrono** cuando el llamador necesita una respuesta inmediata para decidir su siguiente
  paso (validar un token, autorizar una acción, consultar un estado).
- **Mensajería asíncrona (Event Bus)** cuando una acción de negocio debe **notificar a varios
  consumidores independientes** sin que el que publica el evento tenga que conocerlos ni esperar su
  respuesta, y cuando el consumidor no necesita procesar el evento en el mismo instante en que
  ocurrió.

## 2. Comunicación síncrona (REST)

| Origen | Destino | Endpoint / propósito | Por qué es síncrono |
|---|---|---|---|
| API Gateway | Auth Service | validar/renovar JWT | El Gateway no puede enrutar la petición sin saber si el token es válido |
| API Gateway / Transaction / Approval | Authorization Service | `POST /authorize {rol, recurso}` | La decisión de permitir/denegar bloquea la siguiente acción; se protege con retry+backoff (ver `08_integracion_p2.md`) |
| API Gateway | Transaction / Approval / Logging | enrutamiento de las peticiones de negocio | El cliente espera una respuesta HTTP directa |
| Transaction Service | Sistema Core Bancario | `POST /compensacion` | Se necesita el `referenceId` de vuelta para guardar `CoreSubmission` |
| Transaction Service | Cloud Storage / FTP | subir/descargar CSV | Operación de archivo puntual, con respuesta inmediata (URL o confirmación) |

Todas las llamadas síncronas entre microservicios internos van protegidas por **timeout corto** +
**reintentos con backoff exponencial** + **número máximo de intentos configurable** (el mismo patrón
que ya exigía la P2 para el `authz-service`), para que la caída temporal de un servicio no se
propague como una cascada de errores 500.

## 3. Comunicación asíncrona (Event Bus — Kafka/RabbitMQ)

| Evento | Publica | Consume |
|---|---|---|
| `StepApproved` | Approval Service | Logging Service |
| `BatchFullyApproved` | Approval Service | Transaction Service, Logging Service |
| `TransactionsSubmitted` | Transaction Service | Notification Service, Logging Service |

Por qué estos tres eventos son asíncronos y no llamadas REST directas:

- **Desacoplamiento de consumidores**: cuando Approval Service termina el paso 3, no necesita saber
  que existen Transaction Service *y* Logging Service escuchando; si mañana se agrega un cuarto
  consumidor (ej. un servicio de reportería), Approval Service no cambia una línea de código.
- **Resiliencia**: si Notification Service está caído cuando se completa un lote, el evento
  `TransactionsSubmitted` queda en la cola y se procesa en cuanto el servicio vuelve — no se pierde
  el correo a los beneficiarios ni se bloquea el envío al core bancario, que ya ocurrió en el paso
  anterior.
- **Los eventos son la fuente de auditoría de negocio**: cada transición importante del flujo de
  aprobación queda registrada como evento con su propio timestamp, independientemente de si algún
  consumidor estaba disponible en ese momento.

## 4. Contrato de los eventos

Cada evento en el bus lleva como mínimo `{ eventType, batchId, traceId, occurredAt }` — el mismo
`traceId` que se propaga en las llamadas REST síncronas (ver `11_estrategia_logging_centralizado.md`),
para poder correlacionar en Logging Service tanto la parte síncrona como la asíncrona de un mismo
lote de extremo a extremo.
