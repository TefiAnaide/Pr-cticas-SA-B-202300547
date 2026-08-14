# Uso e integración del Servicio de la Practica 2
## Flujo de Autenticación (Login)
1. Usuario envía credenciales → API Gateway
2. API Gateway redirige al Auth Service (P2)
3. Auth Service valida credenciales contra BD encriptada
4. Auth Service genera JWT (12h) y lo almacena en cookie HTTP-only
5. Usuario recibe cookie y puede acceder a los servicios
## Flujo de Autorización (Acceso a endpoints)
1. Usuario hace request a /api/v1/batches/upload
2. API Gateway intercepta y extrae token de la cookie
3. API Gateway consulta al Auth Service (P2) para validar:
   - ¿Token válido?
   - ¿Usuario tiene rol adecuado?
4. Auth Service responde: Permitir/Denegar
5. API Gateway decide si reenvía al servicio destino

# Justificación de la Integración

La integración del módulo de autenticación desarrollado en la Práctica 2 permite reutilizar un componente ya probado y funcional, evitando duplicar esfuerzos. El servicio de autenticación, al estar desacoplado del resto de la arquitectura, puede escalar de forma independiente y ser mantenido por equipos separados, alineándose con los principios de microservicios. El uso de JWT con cookies HTTP-only garantiza un nivel de seguridad adecuado para un sistema bancario, protegiendo los tokens de ataques XSS.

---
# Diseño de Microservicios
## Transaction Service (Servicio de Transacciones)
| Aspecto             | Detalle                                                                                                                                                    |
|---------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Responsabilidad     | Gestión del ciclo de vida de las transacciones: carga de CSV, validación de reglas de negocio, almacenamiento                                              |
| Funcionalidades     | • Recepción de archivos CSV • Validación (saldo, límites, cuentas válidas, fraude) • Almacenamiento en Cloud Storage • Persistencia de transacciones en BD |
| Tecnologías         | Spring Boot / Node.js, PostgreSQL, AWS SDK (S3)                                                                                                            |
| Endpoints           | POST /api/v1/batches/upload, GET /api/v1/batches/{id}/status                                                                                               |
| Eventos que publica | BATCH_VALIDATED, BATCH_REJECTED                                                                                                                            |
| Eventos que consume | BATCH_AUTHORIZED (para actualizar estado)                                                                                                                  |
## Approval Service (Servicio de Aprobación)
| Aspecto             | Detalle                                                                                                                                            |
|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| Responsabilidad     | Gestionar el flujo de aprobación de 3 pasos (Maker-Checker-Authorizer)                                                                             |
| Funcionalidades     | • Crear flujo de aprobación por lote • Registrar acciones de cada paso • Validar que usuarios sean distintos • Enviar a siguiente paso o autorizar |
| Tecnologías         | Spring Boot / Node.js, PostgreSQL                                                                                                                  |
| Endpoints           | POST /api/v1/batches/{id}/submit, POST /api/v1/batches/{id}/approve, POST /api/v1/batches/{id}/authorize                                           |
| Eventos que publica | BATCH_AUTHORIZED (cuando pasa paso 3), STEP_COMPLETED                                                                                              |
| Eventos que consume | BATCH_VALIDATED (inicia flujo)                                                                                                                     |
## Notification Service (Servicio de Notificaciones)
| Aspecto             | Detalle                                                                                        |
|---------------------|------------------------------------------------------------------------------------------------|
| Responsabilidad     | Enviar notificaciones por correo al aprobarse un lote                                          |
| Funcionalidades     | • Generar emails con template • Enviar a proveedor externo (SendGrid/SES) • Manejar reintentos |
| Tecnologías         | Spring Boot / Node.js, SendGrid SDK, Kafka Consumer                                            |
| Endpoints           | POST /api/v1/notifications/send (interna)                                                      |
| Eventos que consume | BATCH_AUTHORIZED (dispara envío de correos)                                                    |
| Eventos que consume | BATCH_VALIDATED (inicia flujo)                                                                 |

## Logging Service (Servicio de Logging)
| Aspecto             | Detalle                                                                                               |
|---------------------|-------------------------------------------------------------------------------------------------------|
| Responsabilidad     | Logging centralizado y auditable                                                                      |
| Funcionalidades     | • Recibir eventos de todos los servicios • Almacenar en Elasticsearch • Interfaz de consulta (Kibana) |
| Tecnologías         | ELK Stack (Elasticsearch, Logstash, Kibana), Kafka                                                    |
| Eventos que consume | Todos los eventos de Kafka (logs)                                                                     |
| Eventos que consume | BATCH_AUTHORIZED (dispara envío de correos)                                                           |
| Eventos que consume | BATCH_VALIDATED (inicia flujo)                                                                        |

## RESUMEN DE SEPARACIÓN DE RESPONSABILIDADES
| Servicio     | Responsabilidad Única                                               | ¿Por qué separado?                                      |
|--------------|---------------------------------------------------------------------|---------------------------------------------------------|
| Transaction  | Gestionar el ciclo de vida de las transacciones y validación de CSV | Cambios en reglas de negocio afectan solo este servicio |
| Approval     | Gestionar flujo de aprobación de 3 pasos                            | Reglas de aprobación pueden cambiar independientemente  |
| Notification | Enviar notificaciones por correo                                    | Puede escalar según volumen de notificaciones           |
| Logging      | Logging centralizado                                                | Servicio independiente para auditoría                   |

##  COMUNICACIÓN ENTRE SERVICIOS
| Comunicación                  | Protocolo           | Uso                                              |
|-------------------------------|---------------------|--------------------------------------------------|
| Usuario → API Gateway         | HTTPS / REST        | Peticiones del frontend                          |
| API Gateway → Servicios       | REST                | Autenticación, autorización, endpoints           |
| Servicios entre sí            | Kafka (asíncrono)   | Eventos: BATCH_VALIDATED, BATCH_AUTHORIZED, logs |
| Transaction → Core Bancario   | REST                | Envío de transacciones al sistema externo        |
| Transaction → Cloud Storage   | AWS SDK / FTP       | Almacenamiento de archivos CSV                   |
| Notification → Email Provider | REST (SendGrid/SES) | Envío de correos electrónicos                    |