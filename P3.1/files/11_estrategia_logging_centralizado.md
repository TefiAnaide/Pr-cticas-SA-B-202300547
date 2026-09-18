# Estrategia de logging centralizado

## 1. Por qué un servicio separado

El enunciado exige "un sistema de logging centralizado y auditable que registre todo lo que ocurre
en el sistema". En una arquitectura de microservicios, si cada servicio escribiera sus propios
logs a disco local, reconstruir qué pasó con un lote específico (que atraviesa Auth, Authorization,
Transaction, Approval y Notification) implicaría entrar a 5 máquinas distintas. **Logging Service**
centraliza la escritura y la consulta, y es el único componente al que **todos** los demás
microservicios escriben.

## 2. Cómo llegan los logs

Dos canales, según el diagrama de arquitectura (`01_arquitectura_general.mermaid`):

1. **Síncrono (REST)**: cada microservicio llama directamente a Logging Service para eventos que se
   quieren confirmar como escritos (ej. decisión de aprobación, resultado de envío al core).
2. **Asíncrono (Event Bus)**: Logging Service también está suscrito al mismo bus de eventos
   (`BUS --> LOG`) que Notification Service, así que eventos de negocio como `StepApproved` o
   `BatchFullyApproved` quedan registrados sin que el servicio que los publica tenga que hacer una
   llamada adicional.

Se prefiere el canal asíncrono para no acoplar la latencia de una transacción de negocio a la
disponibilidad de Logging Service; el canal síncrono se reserva para los pocos eventos que
necesitan confirmación de escritura antes de continuar (ej. un log de seguridad crítico).

## 3. Qué se registra (`LOG_ENTRY`)

```
LOG_ENTRY { id, service, level, traceId, message, timestamp }
```

- **`traceId`**: un identificador único generado en el API Gateway al recibir la petición original y
  propagado por cabecera (`X-Trace-Id`) a través de todos los servicios involucrados
  (Auth → Authorization → Approval → Transaction → Notification). Es lo que permite reconstruir la
  historia completa de un lote (`batchId`) o de una sesión, filtrando por `traceId` en un solo lugar.
- **`level`**: `INFO` (operación normal), `WARN` (reintento de Authorization Service, renovación de
  JWT), `ERROR` (rechazo de autorización agotando reintentos, fallo al enviar al core bancario),
  `AUDIT` (decisiones de aprobación/rechazo — no se pueden borrar ni modificar, por requerimiento de
  auditoría bancaria).
- **`service`**: nombre del microservicio emisor, para poder filtrar/alertar por origen.

## 4. Qué hace "auditable"

- Los registros de nivel `AUDIT` (aprobaciones, rechazos, envíos al core, accesos a datos de
  clientes) son de solo-append: ningún servicio expone un endpoint de `UPDATE`/`DELETE` sobre
  `LOG_ENTRY`.
- Cada decisión de Authorization Service (`allowed: true/false`) se loguea con el `rol` y el
  `recurso` evaluado, para poder demostrar después quién tuvo o no permiso para una acción.
- Logging Service expone una API de solo lectura (consulta por `traceId`, `batchId`, rango de
  fechas, `service`, `level`) para los equipos de auditoría/cumplimiento, separada de la API de
  ingestión que usan los demás microservicios.

## 5. Dónde se persiste

`DB Logging` es independiente del resto (requisito de una base de datos por microservicio). Al ser
un volumen de escritura alto y de consulta principalmente por `traceId`/rango de tiempo, es un buen
candidato para un motor orientado a series de tiempo/documentos (ej. Elasticsearch, un almacén
columnar, o al menos una tabla particionada por fecha si se usa una relación clásica), aunque el
detalle de motor específico queda fuera del alcance de esta práctica y se documenta como decisión
técnica abierta.
